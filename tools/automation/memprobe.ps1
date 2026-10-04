# Read-only memory/handle probe for kenshi_x64 (no injection, no debugger).
# Usage: powershell -File memprobe.ps1 [-Regions] [-Label txt] [-Csv path]
# Prints one line: time label priv ws threads handles File Semaphore Event Thread privCommitMB nAllocs bigAllocs(>=16MB) bigMB
param([switch]$Regions,[string]$Label="",[string]$Csv="")
$src=@'
using System;using System.Runtime.InteropServices;using System.Collections.Generic;
public static class KMemProbe{
[StructLayout(LayoutKind.Sequential)] public struct MBI{public IntPtr Base;public IntPtr AllocBase;public uint AllocProt;public uint p1;public IntPtr Size;public uint State;public uint Protect;public uint Type;public uint p2;}
[DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a,bool i,int pid);
[DllImport("kernel32.dll")] static extern IntPtr VirtualQueryEx(IntPtr h,IntPtr a,out MBI m,IntPtr l);
[DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
[DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int c,IntPtr b,int l,out int r);
[DllImport("ntdll.dll")] static extern int NtQueryObject(IntPtr h,int c,IntPtr b,int l,out int r);
public static Dictionary<string,int> Handles(long pid){int len=1<<24;IntPtr b;int r;
 while(true){b=Marshal.AllocHGlobal(len);int st=NtQuerySystemInformation(64,b,len,out r);if(st==unchecked((int)0xC0000004)){Marshal.FreeHGlobal(b);len*=2;continue;}break;}
 var names=new Dictionary<int,string>();IntPtr t=Marshal.AllocHGlobal(1<<20);
 if(NtQueryObject(IntPtr.Zero,3,t,1<<20,out r)==0){int num=Marshal.ReadInt32(t);long off=8;
  for(int i=0;i<num;i++){IntPtr ti=new IntPtr(t.ToInt64()+off);int nl=Marshal.ReadInt16(ti);int maxl=Marshal.ReadInt16(ti,2);string nm=Marshal.PtrToStringUni(Marshal.ReadIntPtr(ti,8),nl/2);names[Marshal.ReadByte(ti,0x5A)]=nm;off+=0x68+((maxl+7)&~7);}}
 Marshal.FreeHGlobal(t);
 long n=Marshal.ReadInt64(b);var cnt=new Dictionary<string,int>();
 for(long i=0;i<n;i++){IntPtr e=new IntPtr(b.ToInt64()+16+i*40);if(Marshal.ReadInt64(e,8)!=pid)continue;int ti=Marshal.ReadInt16(e,30);string nm;if(!names.TryGetValue(ti,out nm))nm="t"+ti;int v;cnt.TryGetValue(nm,out v);cnt[nm]=v+1;}
 Marshal.FreeHGlobal(b);return cnt;}
public static long[] Regions(int pid,bool dump){IntPtr h=OpenProcess(0x0400,false,pid);var alloc=new Dictionary<long,long>();long addr=0;MBI m;long pc=0;
 while(VirtualQueryEx(h,new IntPtr(addr),out m,(IntPtr)Marshal.SizeOf(typeof(MBI)))!=IntPtr.Zero){long sz=m.Size.ToInt64();
  if(m.State==0x1000&&m.Type==0x20000){pc+=sz;long ab=m.AllocBase.ToInt64();long v;alloc.TryGetValue(ab,out v);alloc[ab]=v+sz;}
  addr=m.Base.ToInt64()+sz;if(addr<=0)break;}
 CloseHandle(h);long big=0,bigMB=0;var sizes=new Dictionary<long,int>();
 foreach(var kv in alloc){if(kv.Value>=(16L<<20)){big++;bigMB+=kv.Value>>20;}long k=kv.Value>>20;int c;sizes.TryGetValue(k,out c);sizes[k]=c+1;}
 if(dump){var l=new List<KeyValuePair<long,int>>(sizes);l.Sort((a,b2)=>(b2.Key*b2.Value).CompareTo(a.Key*a.Value));for(int i=0;i<20&&i<l.Count;i++)Console.WriteLine("  sizeMB="+l[i].Key+" count="+l[i].Value+" totalMB="+(l[i].Key*l[i].Value));}
 return new long[]{pc>>20,alloc.Count,big,bigMB};}}
'@
Add-Type $src
$p=Get-Process kenshi_x64 -ErrorAction SilentlyContinue
if(-not $p){"kenshi_x64 not running";exit 1}
$h=[KMemProbe]::Handles($p.Id); $r=[KMemProbe]::Regions($p.Id,[bool]$Regions)
function g($k){ if($h.ContainsKey($k)){$h[$k]}else{0} }
$line="{0},{1},{2:F0},{3:F0},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13}" -f (Get-Date -f HH:mm:ss),$Label,($p.PrivateMemorySize64/1MB),($p.WorkingSet64/1MB),$p.Threads.Count,$p.HandleCount,(g 'File'),(g 'Semaphore'),(g 'Event'),(g 'Thread'),$r[0],$r[1],$r[2],$r[3]
if($Csv){ if(-not (Test-Path $Csv)){"time,label,privMB,wsMB,threads,handles,File,Semaphore,Event,Thread,privCommitMB,nAllocs,big16MB,bigMB" | Out-File $Csv -Encoding utf8}; $line | Out-File $Csv -Append -Encoding utf8 }
$line
