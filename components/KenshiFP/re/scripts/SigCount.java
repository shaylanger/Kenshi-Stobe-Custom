// KenshiFP: count matches of a wildcarded byte signature in the program.
// Read-only. Arg: "AA BB ?? CC ..." (hex bytes, ?? = wildcard); multiple sigs
// separated by ';'. Prints every match address (capped at 8 per sig).
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;

public class SigCount extends GhidraScript {
    long base = 0x140000000L;

    @Override
    public void run() throws Exception {
        for (String sig : getScriptArgs()[0].split(";")) {
            String[] toks = sig.trim().split("\\s+");
            byte[] pat = new byte[toks.length], msk = new byte[toks.length];
            for (int i = 0; i < toks.length; i++) {
                if (toks[i].equals("??")) { pat[i] = 0; msk[i] = 0; }
                else { pat[i] = (byte) Integer.parseInt(toks[i], 16); msk[i] = (byte) 0xff; }
            }
            println("sig (" + toks.length + " bytes):");
            Address at = currentProgram.getMinAddress();
            int n = 0;
            while (n < 8) {
                at = currentProgram.getMemory().findBytes(at, pat, msk, true, monitor);
                if (at == null) break;
                println("  match @RVA 0x" + Long.toHexString(at.getOffset() - base));
                n++;
                at = at.add(1);
            }
            println("  total shown: " + n + (n >= 8 ? "+ (capped)" : ""));
        }
    }
}
