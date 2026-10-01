import sys

root = sys.argv[1]


def patch(rel, pairs):
    path = root + '/' + rel
    s = open(path).read()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, (rel, old[:100], n)
        s = s.replace(old, new)
    open(path, 'w').write(s)
    print('patched', rel)


# ---------------------------------------------------------------- Comm.h
patch('src/Comm.h', [
    ("""void AsyncPostToStobeSerial(const std::wstring &endpoint,
                            const std::string &jsonData);""",
     """void AsyncPostToStobeSerial(const std::wstring &endpoint,
                            const std::string &jsonData);
// Same serial channel with a lane (Stobe::EventPolicy::Priority): high-priority
// posts are sent before queued lower-priority ones, and on overflow the lowest
// lane is dropped first.
void AsyncPostToStobeSerialWithPriority(const std::wstring &endpoint,
                                        const std::string &jsonData,
                                        int priority);"""),
])

# ---------------------------------------------------------------- Comm.cpp
patch('src/Comm.cpp', [
    ("""struct SerialHttpTask {
  std::wstring endpoint;
  std::string data;
  unsigned long playthroughEpoch;
};

std::deque<SerialHttpTask> g_serialHttpQueue;""",
     """struct SerialHttpTask {
  std::wstring endpoint;
  std::string data;
  unsigned long playthroughEpoch;
};

// One FIFO per priority lane (index = Stobe::EventPolicy::Priority).
const int kSerialHttpLaneCount = 3;
std::deque<SerialHttpTask> g_serialHttpQueue[kSerialHttpLaneCount];"""),
    ("""bool PopSerialHttpTask(SerialHttpTask &taskOut) {
  bool hasTask = false;
  EnterCriticalSection(&g_serialHttpQueueMutex);
  if (!g_serialHttpQueue.empty()) {
    taskOut = g_serialHttpQueue.front();
    g_serialHttpQueue.pop_front();
    hasTask = true;
  }
  LeaveCriticalSection(&g_serialHttpQueueMutex);
  return hasTask;
}""",
     """size_t SerialHttpQueueDepthLocked() {
  size_t depth = 0;
  for (int lane = 0; lane < kSerialHttpLaneCount; ++lane) {
    depth += g_serialHttpQueue[lane].size();
  }
  return depth;
}

bool PopSerialHttpTask(SerialHttpTask &taskOut) {
  bool hasTask = false;
  EnterCriticalSection(&g_serialHttpQueueMutex);
  for (int lane = 0; lane < kSerialHttpLaneCount && !hasTask; ++lane) {
    if (!g_serialHttpQueue[lane].empty()) {
      taskOut = g_serialHttpQueue[lane].front();
      g_serialHttpQueue[lane].pop_front();
      hasTask = true;
    }
  }
  LeaveCriticalSection(&g_serialHttpQueueMutex);
  return hasTask;
}"""),
    ("""void EnqueueSerialHttpPost(const std::wstring &endpoint,
                           const std::string &jsonData) {
  EnsureSerialHttpWorkerStarted();""",
     """void EnqueueSerialHttpPost(const std::wstring &endpoint,
                           const std::string &jsonData, int priority) {
  EnsureSerialHttpWorkerStarted();
  if (priority < 0) {
    priority = 0;
  } else if (priority >= kSerialHttpLaneCount) {
    priority = kSerialHttpLaneCount - 1;
  }"""),
    ("""  EnterCriticalSection(&g_serialHttpQueueMutex);
  if (g_serialHttpQueue.size() >= kSerialHttpQueueCap) {
    g_serialHttpQueue.pop_front();
    dropped = true;
    InterlockedIncrement(&g_serialHttpDropped);
  }
  SerialHttpTask task;
  task.playthroughEpoch = PlaythroughSession::Context();
  task.endpoint = endpoint;
  task.data = jsonData;
  g_serialHttpQueue.push_back(task);
  queueDepth = g_serialHttpQueue.size();""",
     """  EnterCriticalSection(&g_serialHttpQueueMutex);
  if (SerialHttpQueueDepthLocked() >= kSerialHttpQueueCap) {
    // Make room from the least important lane first: combat telemetry goes
    // before healing, trades and dialogue ever do.
    for (int lane = kSerialHttpLaneCount - 1; lane >= 0; --lane) {
      if (!g_serialHttpQueue[lane].empty()) {
        g_serialHttpQueue[lane].pop_front();
        dropped = true;
        InterlockedIncrement(&g_serialHttpDropped);
        break;
      }
    }
  }
  SerialHttpTask task;
  task.playthroughEpoch = PlaythroughSession::Context();
  task.endpoint = endpoint;
  task.data = jsonData;
  g_serialHttpQueue[priority].push_back(task);
  queueDepth = SerialHttpQueueDepthLocked();"""),
    ("""    Log("SERIAL_HTTP: queue overflow; dropped oldest event posts total_dropped=" +""",
     """    Log("SERIAL_HTTP: queue overflow; dropped lowest-priority event posts total_dropped=" +"""),
    ("""void AsyncPostToStobeSerial(const std::wstring &endpoint,
                            const std::string &jsonData) {
  if (!PlaythroughSession::Allowed(PlaythroughSession::Context())) return;
  EnqueueSerialHttpPost(endpoint, jsonData);
}""",
     """void AsyncPostToStobeSerial(const std::wstring &endpoint,
                            const std::string &jsonData) {
  AsyncPostToStobeSerialWithPriority(endpoint, jsonData, 1);
}

void AsyncPostToStobeSerialWithPriority(const std::wstring &endpoint,
                                        const std::string &jsonData,
                                        int priority) {
  if (!PlaythroughSession::Allowed(PlaythroughSession::Context())) return;
  EnqueueSerialHttpPost(endpoint, jsonData, priority);
}"""),
])

# ---------------------------------------------------------------- Utils.cpp
patch('src/Utils.cpp', [
    ("""  EnterCriticalSection(&g_eventMutex);
  GameEvent ev;
  ev.type = type;""",
     """  // Combat telemetry repeats many times a second in big fights. Send the same
  // attacker/target pair at most once per short window so the serial queue
  // keeps up and important events (healing, trades, dialogue) are not delayed.
  const std::uint32_t debounceWindowMs =
      Stobe::EventPolicy::DebounceWindowMsForEventType(normalizedType);
  if (debounceWindowMs > 0) {
    static Stobe::EventPolicy::Debouncer eventDebouncer(512);
    static DWORD lastDebounceLogTick = 0;
    const std::string debounceKey = Stobe::EventPolicy::DebounceKey(
        normalizedType, actor, actorSerial, target, targetSerial);
    EnterCriticalSection(&g_eventMutex);
    const DWORD debounceNow = GetTickCount();
    const bool debounced =
        eventDebouncer.ShouldDrop(debounceKey, debounceNow, debounceWindowMs);
    const std::uint32_t debouncedTotal = eventDebouncer.DroppedCount();
    const bool logDebounce =
        debounced && (debounceNow - lastDebounceLogTick) >= 10000;
    if (logDebounce) {
      lastDebounceLogTick = debounceNow;
    }
    LeaveCriticalSection(&g_eventMutex);
    if (debounced) {
      if (logDebounce) {
        Log("EVENT_STREAM: debounced repeated " + normalizedType +
            " events total=" + ToString((int)debouncedTotal));
      }
      return;
    }
  }

  EnterCriticalSection(&g_eventMutex);
  GameEvent ev;
  ev.type = type;"""),
    ("""  AsyncPostToStobeSerial(endpoint, "");
  Log("EVENT_STREAM: queued type=" + eventType +""",
     """  const int eventPriority =
      Stobe::EventPolicy::PriorityForEventType(normalizedType);
  AsyncPostToStobeSerialWithPriority(endpoint, "", eventPriority);
  Log("EVENT_STREAM: queued type=" + eventType +
      " priority=" + ToString(eventPriority) +"""),
])

# ---------------------------------------------------------------- build lists
patch('CMakeLists.txt', [
    ("""  src/StobeTiming.cpp""", """  src/StobeTiming.cpp
  src/StobeEventPolicy.cpp"""),
])
patch('tests/cpp/CMakeLists.txt', [
    ("""  ../../src/StobeTiming.cpp""", """  ../../src/StobeTiming.cpp
  ../../src/StobeEventPolicy.cpp"""),
])
