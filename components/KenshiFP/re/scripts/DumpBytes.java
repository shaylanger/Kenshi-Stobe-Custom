// Dump raw bytes at given RVAs (for signature authoring). Arg: "rva,len[;rva,len...]"
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;

public class DumpBytes extends GhidraScript {
    long base = 0x140000000L;
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        for (String part : a[0].split(";")) {
            String[] p = part.split(",");
            long rva = Long.parseLong(p[0].replace("0x",""),16);
            int len = Integer.parseInt(p[1].replace("0x",""),16);
            Address addr = toAddr(base + rva);
            byte[] bytes = getBytes(addr, len);
            StringBuilder sb = new StringBuilder();
            for (byte bb : bytes) sb.append(String.format("%02X ", bb & 0xff));
            println("RVA 0x" + Long.toHexString(rva) + ": " + sb);
        }
    }
}
