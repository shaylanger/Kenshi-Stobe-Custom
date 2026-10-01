// KenshiFP: locate MSVC x64 vtables from RTTI class names, dump leading slots,
// and list code refs to each vtable (constructor/destructor candidates).
// Read-only. Arg: semicolon-separated bare class names, e.g.
// "FloatingProgressBar;InfoText;ScreenLabelInterface;CharacterNameTag"
// Chain: ".?AV<name>@@" string -> TypeDescriptor (str-0x10) -> COL (+0xC holds
// TD RVA, +0x14 holds COL's own RVA) -> vftable (8-byte ptr to COL, vft = hit+8).
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

public class RttiVtables extends GhidraScript {
    long base = 0x140000000L;

    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        String[] names = (a != null && a.length > 0) ? a[0].split(";")
            : new String[]{ "FloatingProgressBar" };
        for (String nm : names) locate(nm.trim());
    }

    void locate(String name) throws Exception {
        String needle = ".?AV" + name + "@@";
        println("\n######## " + name + " ########");
        byte[] pat = needle.getBytes("ASCII");
        Address str = findPat(null, pat);
        boolean any = false;
        while (str != null) {
            // require terminator so "InfoText" doesn't match "InfoTextFoo"
            byte after = getByte(str.add(pat.length));
            if (after == 0) { any = true; handleTd(name, str.subtract(0x10)); }
            str = findPat(str.add(1), pat);
        }
        if (!any) println("  RTTI name not found");
    }

    void handleTd(String name, Address td) throws Exception {
        long tdRva = td.getOffset() - base;
        println("  TypeDescriptor @RVA 0x" + Long.toHexString(tdRva));
        byte[] tdPat = leInt((int) tdRva);
        Address hit = findPat(null, tdPat);
        while (hit != null) {
            Address col = hit.subtract(0xC);
            try {
                int sig = getInt(col);
                int self = getInt(col.add(0x14));
                if (sig == 1 && (self & 0xffffffffL) == col.getOffset() - base) {
                    long off = getInt(col.add(4)) & 0xffffffffL; // vbase offset of this vftable
                    println("  COL @RVA 0x" + Long.toHexString(col.getOffset() - base)
                            + " (subobject offset 0x" + Long.toHexString(off) + ")");
                    byte[] colPat = leLong(col.getOffset());
                    Address p = findPat(null, colPat);
                    while (p != null) {
                        Address vft = p.add(8);
                        dumpVtable(vft);
                        p = findPat(p.add(1), colPat);
                    }
                }
            } catch (Exception e) { /* unreadable candidate */ }
            hit = findPat(hit.add(1), tdPat);
        }
    }

    void dumpVtable(Address vft) throws Exception {
        println("  vftable @RVA 0x" + Long.toHexString(vft.getOffset() - base));
        for (int i = 0; i < 14; i++) {
            long t;
            try { t = getLong(vft.add(i * 8L)); } catch (Exception e) { break; }
            if (t < base || t > base + 0x2000000L) break;
            Function f = getFunctionAt(toAddr(t));
            if (f == null) f = getFunctionContaining(toAddr(t));
            println("    vt[" + i + "] 0x" + Long.toHexString(t - base)
                    + (f == null ? "" : " " + f.getName()));
        }
        ReferenceIterator it = currentProgram.getReferenceManager().getReferencesTo(vft);
        while (it.hasNext()) {
            Reference r = it.next();
            Function f = getFunctionContaining(r.getFromAddress());
            println("    ref from " + r.getFromAddress() + " in "
                    + (f == null ? "(no func)" : f.getName() + " @0x"
                       + Long.toHexString(f.getEntryPoint().getOffset() - base)));
        }
    }

    byte[] leInt(int v) {
        return new byte[]{ (byte) v, (byte) (v >> 8), (byte) (v >> 16), (byte) (v >> 24) };
    }
    byte[] leLong(long v) {
        byte[] b = new byte[8];
        for (int i = 0; i < 8; i++) b[i] = (byte) (v >> (8 * i));
        return b;
    }
    Address findPat(Address from, byte[] pat) {
        Address start = from == null ? currentProgram.getMinAddress() : from;
        return currentProgram.getMemory().findBytes(start, pat, null, true, monitor);
    }
}
