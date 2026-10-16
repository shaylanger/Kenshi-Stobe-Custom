#!/usr/bin/env python3
"""Source-contract checks for NC12 (natural mine node product, camp/end diagnostics).
Reads the added lines of nc12-over-nc11.patch. Run: python3 tests/nc12_source_tests.py"""
from pathlib import Path
import unittest

PATCH = Path(__file__).resolve().parents[1] / "nc12-over-nc11.patch"
ADDED = "\n".join(l[1:] for l in PATCH.read_text(encoding="utf-8", errors="replace").splitlines()
                  if l.startswith("+") and not l.startswith("+++"))


class Nc12SourceTests(unittest.TestCase):
    def test_mine_source_no_longer_requires_production_building(self):
        self.assertIn("if(!production) { // NC12 (row 25-b)", ADDED)
        self.assertIn("InventorySection* section=NaturalOutput(b,resolved,how,clause);", ADDED)
        self.assertIn("item=resolved;reason.clear();return true;", ADDED)

    def test_exact_section_has_natural_branch(self):
        self.assertIn("!b->_NV_getProductionBuilding()) {", ADDED)
        self.assertIn("return NaturalOutput(b,it,how,clause);", ADDED)

    def test_natural_product_from_inventory_then_gamedata(self):
        self.assertIn("ActivityMine::ResolveNaturalProduct(in,resolved,how)", ADDED)
        self.assertIn("gd->objectReferences.begin()", ADDED)
        self.assertIn("ref->type!=ITEM", ADDED)

    def test_natural_lease_growth_is_proximity_bounded(self):
        self.assertIn("dx*dx+dz*dz>60.0f*60.0f", ADDED)
        self.assertIn("l.natural=!b->_NV_getProductionBuilding();", ADDED)

    def test_mine_diag_has_new_clauses(self):
        for c in ("natural_resolved_inventory", "natural_resolved_gamedata", "natural_product_unresolved",
                  "natural_output_section_ambiguous", "natural_mixed_items"):
            self.assertIn(c, ADDED)
        self.assertIn("ACTIVITY_MINE_EXACT_DIAG", ADDED)

    def test_camp_town_diag(self):
        self.assertIn("ACTIVITY_CAMP_TOWNS_DIAG raw=", ADDED)
        self.assertIn("DiagTownEntries(entries,out.size());", ADDED)
        for c in ("known_name_empty", "not_formal_type", "radius_out_of_range", "not_TOWN_datatype"):
            self.assertIn(c, ADDED)
        self.assertIn("if (i < 12)", ADDED)

    def test_end_and_verify_diag(self):
        self.assertIn("ACTIVITY_END_DIAG where=publish", ADDED)
        self.assertIn('DiagEnd("goal_stop"', ADDED)
        self.assertIn('DiagEnd("replan_exhausted"', ADDED)
        self.assertIn("ACTIVITY_VERIFY_DIAG agreement=", ADDED)
        self.assertIn("Stobe::Activity::ActivityEndLogSink=&::Log;", ADDED)


if __name__ == "__main__":
    unittest.main()
