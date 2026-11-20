#include "bst.hpp"
#include <set>
#include <random>
#include <cassert>
int main(){BST t;std::set<int> ref;std::mt19937 rng(42);
for(int i=0;i<10000;++i){int k=int(rng()%101)-50;switch(rng()%3){case 0:assert(t.insert(k)==ref.insert(k).second);break;case 1:assert(t.erase(k)==bool(ref.erase(k)));break;default:assert(t.find(k)==bool(ref.count(k)));}
assert(t.ordered()==std::vector<int>(ref.begin(),ref.end()));}
t.clear();for(int i=0;i<5000;++i)assert(t.insert(i));assert(t.ordered().size()==5000);assert(t.snapshot("test").find("BST1 5000 test")==0);t.clear();assert(t.ordered().empty());
for(int n : {1,50,75,100,101,10000}) {t.big_demo(n);auto v=t.ordered();assert(v.size()==static_cast<size_t>(n));for(int i=0;i<n;++i)assert(v[i]==i+1);}
auto before=t.ordered();bool rejected=false;try{t.big_demo(0);}catch(const std::runtime_error&){rejected=true;}assert(rejected && t.ordered()==before);
}
