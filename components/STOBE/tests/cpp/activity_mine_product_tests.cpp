// NC12 (row 25-b): offline tests of the natural-mine product decision. g++ -std=c++03
#include "ActivityMineProduct.h"
#include <cstdio>
using namespace Stobe::ActivityMine;
static int fails=0;
static void Expect(const char* name,const ProductInputs& in,const char* clause,const char* item,const char* how) {
 std::string it,h; const std::string c=ResolveNaturalProduct(in,it,h);
 if(c!=clause || it!=item || h!=how) {printf("FAIL %s: clause=%s item=%s how=%s\n",name,c.c_str(),it.c_str(),h.c_str());++fails;}
}
int main() {
 ProductInputs in;
 // iron node, inventory holds iron: resolves from the inventory
 in.stored.push_back("iron-ore"); in.stored.push_back("iron-ore");
 Expect("inventory resolves",in,"","iron-ore","inventory");
 in.expected="iron-ore"; Expect("expected matches",in,"","iron-ore","inventory");
 in.expected="copper-ore"; Expect("expected mismatch",in,"natural_product_mismatch","","inventory");
 in=ProductInputs(); in.stored.push_back("iron-ore"); in.stored.push_back("copper-ore");
 Expect("mixed stored",in,"natural_mixed_items","","");
 in=ProductInputs(); in.storedBad=true; Expect("null stored",in,"stored_item_null_or_nodata","","");
 in=ProductInputs(); in.stored.push_back(""); Expect("empty id stored",in,"stored_item_null_or_nodata","","");
 // empty inventory: fall back to the game data item reference
 in=ProductInputs(); in.dataItems.push_back("iron-ore");
 Expect("gamedata resolves",in,"","iron-ore","gamedata");
 in.expected="iron-ore"; Expect("gamedata expected ok",in,"","iron-ore","gamedata");
 in.expected="x"; Expect("gamedata expected mismatch",in,"natural_product_mismatch","","gamedata");
 in=ProductInputs(); in.dataItems.push_back("iron-ore"); in.dataItems.push_back("stone");
 Expect("gamedata ambiguous",in,"natural_product_ambiguous","","");
 in=ProductInputs(); Expect("nothing known",in,"natural_product_unresolved","","");
 // inventory wins over game data
 in=ProductInputs(); in.stored.push_back("iron-ore"); in.dataItems.push_back("stone");
 Expect("inventory wins",in,"","iron-ore","inventory");
 if(fails) {printf("RESULT NC12-MINE-PRODUCT-TESTS FAIL %d\n",fails);return 1;}
 printf("RESULT NC12-MINE-PRODUCT-TESTS PASS 11/11\n");return 0;
}
