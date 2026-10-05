import unittest
from capture_native_ranged import parse_page, assess

def event(seq,kind=2,ammo=1):
    return dict(seq=seq,ms=seq,frame=seq,kind=kind,actor=1,ranged=2,gun=3,target=4,
                state=3,mode=1,ammo=ammo,stat=37,dt=.016)
def token(row):
    return ",".join(format(row[k],"x") if k in ("actor","ranged","gun","target")
                    else str(row[k]) for k in row)
def trace():
    return [event(1),event(2,3),event(3,4,0),event(4,1),
            event(5,3),event(6,4,0),event(7,1),event(8,3),event(9,4,0)]

class NativeTraceTests(unittest.TestCase):
    def test_flattened_reply(self):
        row=event(1)
        header="capture=7 next=2 oldest=1 lost=0 count=1 "
        meta,rows=parse_page(header+token(row)+" through=1 more=0",7,0)
        self.assertEqual(rows,[row]); self.assertEqual(meta["through"],1)
    def test_lost_or_reset_capture_fails(self):
        for capture,lost in ((8,0),(7,1)):
            with self.assertRaises(ValueError):
                parse_page(f"capture={capture} next=2 oldest=1 lost={lost} count=1 through=0 more=1",7,0)
    def test_truncation_gap_bounds_and_footer_fail(self):
        header="capture=7 next=2 oldest=1 lost=0 count=1 "
        for row,footer in ((token(event(2)),"through=1 more=0"),
                           (token(event(1)).rsplit(",",1)[0],"through=1 more=0"),
                           (token(event(1)),"through=0 more=0"),
                           (token(event(1)),"through=1 more=1")):
            with self.assertRaises(ValueError): parse_page(header+row+" "+footer,7,0)
    def test_actual_shot_observations(self):
        result=assess(trace(),3)
        self.assertEqual(result["shots"],3); self.assertEqual(result["ammo_increases"],2)
    def test_callback_without_ammo_consumption_fails(self):
        rows=trace(); rows[2]["ammo"]=1
        with self.assertRaises(ValueError): assess(rows,3)
    def test_missing_animation_or_actor_or_pairs_fails(self):
        for rows in ([],trace()[1:],trace()[:-1]):
            with self.assertRaises(ValueError): assess(rows,3)
        rows=trace(); rows[3]["actor"]=0
        with self.assertRaises(ValueError): assess(rows,3)
    def test_identity_or_weapon_change_fails(self):
        for field in ("actor","target","gun","stat"):
            rows=trace(); rows[2][field]=99
            with self.assertRaises(ValueError): assess(rows,3)
    def test_insufficient_cycles_fails(self):
        with self.assertRaises(ValueError): assess(trace()[:3],3)
if __name__=="__main__": unittest.main()
