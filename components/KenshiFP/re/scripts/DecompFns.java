// KenshiFP: decompile the given function RVAs in full. Read-only.
// Arg: comma-separated function RVAs, e.g. "0xa2ad10,0xa2c100".
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;

public class DecompFns extends GhidraScript {
    long base = 0x140000000L;
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);
        for (String s : a[0].split(",")) {
            long rva = Long.parseLong(s.trim().replace("0x",""), 16);
            Function f = getFunctionAt(toAddr(base + rva));
            if (f == null) { println("no function @0x" + Long.toHexString(rva)); continue; }
            println("\n==== " + f.getName() + " @0x" + Long.toHexString(rva) + " ====");
            DecompileResults r = dec.decompileFunction(f, 120, monitor);
            println(r.getDecompiledFunction() == null ? "(decompile failed)"
                    : r.getDecompiledFunction().getC());
        }
    }
}
