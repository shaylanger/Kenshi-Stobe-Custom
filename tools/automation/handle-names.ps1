# handle-names.ps1: read-only. Groups kenshi_x64 File (by access mask + path) and Semaphore handles: DuplicateHandle copies into this process, NtQueryObject names, copies closed.
param([int]$Max=3000)
$src=@'
using System;using System.Runtime.InteropServices;using System.Collections.Generic;using System.Threading;
public static class KHN2{
[DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a,bool i,int pid);
[DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
[DllImport("kernel32.dll")] static extern bool DuplicateHandle(IntPtr sp,IntPtr sh,IntPtr tp,out IntPtr th,uint a,bool i,uint o);
[DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
[DllImport("kernel32.dll")] static extern uint GetFileType(IntPtr h);
[DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int c,IntPtr b,int l,out int r);
[DllImport("ntdll.dll")] static extern int NtQueryObject(IntPtr h,int c,IntPtr b,int l,out int r);
static string Name(IntPtr h){IntPtr b=Marshal.AllocHGlobal(4096);int r;string s=null;if(NtQueryObject(h,1,b,4096,out r)==0){int l=Marshal.ReadInt16(b);if(l>0)s=Marshal.PtrToStringUni(Marshal.ReadIntPtr(b,8),l/2);}Marshal.FreeHGlobal(b);return s;}
public static string Run(int pid,int max,int fileType,int semType){int len=1<<24;IntPtr b;int r;
 while(true){b=Marshal.AllocHGlobal(len);int st=NtQuerySystemInformation(64,b,len,out r);if(st==unchecked((int)0xC0000004)){Marshal.FreeHGlobal(b);len*=2;continue;}break;}
 IntPtr hp=OpenProcess(0x0040,false,pid); if(hp==IntPtr.Zero) return "OpenProcess(DUP_HANDLE) failed";
 long n=Marshal.ReadInt64(b);var groups=new Dictionary<string,int>();int done=0;
 for(long i=0;i<n&&done<max;i++){IntPtr e=new IntPtr(b.ToInt64()+16+i*40);if(Marshal.ReadInt64(e,8)!=pid)continue;int ti=Marshal.ReadInt16(e,30);if(ti!=fileType&&ti!=semType)continue;
  uint acc=(uint)Marshal.ReadInt32(e,24); if(ti==fileType && (acc==0x0012019f||acc==0x00120189||acc==0x0012008d||acc==0x00100000)) { } // query anyway, but pipes guarded by GetFileType below
  IntPtr hv=Marshal.ReadIntPtr(e,16);IntPtr d;if(!DuplicateHandle(hp,hv,GetCurrentProcess(),out d,0,false,2))continue;done++;
  string key;
  if(ti==semType){string nm=Name(d);key="Semaphore:"+(nm??"<unnamed>");}
  else{uint ft=GetFileType(d);
   if(ft==3){key="File:pipe";}
   else{string nm=null;Thread t=new Thread(()=>{nm=Name(d);});t.IsBackground=true;t.Start();if(!t.Join(200)){key="File:<hang>";}else{
     nm=nm??"<noname>";
     nm=System.Text.RegularExpressions.Regex.Replace(nm,@"\d+","#");key="File:acc="+acc.ToString("X")+" "+nm;}}}
  CloseHandle(d);int v;groups.TryGetValue(key,out v);groups[key]=v+1;}
 CloseHandle(hp);Marshal.FreeHGlobal(b);
 var l=new List<KeyValuePair<string,int>>(groups);l.Sort((x,y)=>y.Value.CompareTo(x.Value));string s="sampled="+done+"\n";
 for(int i=0;i<25&&i<l.Count;i++)s+=l[i].Value+"  "+l[i].Key+"\n";return s;}}
'@
Add-Type $src
$p=Get-Process kenshi_x64
[KHN2]::Run($p.Id,$Max,37,19)
