import unittest
from capture_native_melee import parse,assess,FIELDS,HEX,FLOAT
class MeleeTraceTests(unittest.TestCase):
    def row(self,state=4):
        row=dict.fromkeys(FIELDS,0)
        row.update(actor=1,combat=2,movement=3,active=1,state=state,frame_dt=.016)
        if state==0:row["technique"]=4
        return row
    def test_parser(self):
        row=self.row()
        text=" ".join(k+"="+(format(row[k],"x") if k in HEX else str(row[k])) for k in FIELDS)
        self.assertEqual(parse(text),row)
        with self.assertRaisesRegex(ValueError,"incomplete"):parse("actor=1")
        with self.assertRaisesRegex(ValueError,"nonfinite"):parse(text.replace("frame_dt=0.016","frame_dt=nan"))
        with self.assertRaisesRegex(ValueError,"paused"):parse(text.replace("frame_dt=0.016","frame_dt=0"))
    def test_cycle_gate(self):
        rows=[self.row(s) for s in [4,0,0,4,0,0,4,0,0,4]*3]
        rows[0].update(dead=1,dead_left=.2)
        self.assertEqual(assess(rows,3)["observed_chop_entries"],9)
        rows[5]["actor"]=99
        with self.assertRaisesRegex(ValueError,"identity"):assess(rows,3)
    def test_stuck_state_is_not_repeated_swing(self):
        rows=[self.row(0) for _ in range(30)]
        with self.assertRaisesRegex(ValueError,"insufficient observed"):assess(rows,3)
    def test_missing_recovery_or_stopped_fight(self):
        rows=[self.row(s) for s in [4,0]*15]
        with self.assertRaisesRegex(ValueError,"recovery"):assess(rows,3)
        rows[0]["active"]=0
        with self.assertRaisesRegex(ValueError,"fight stopped"):assess(rows,3)
if __name__=="__main__":unittest.main()
