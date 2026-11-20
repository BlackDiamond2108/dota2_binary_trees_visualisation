#pragma once
#include <memory>
#include <vector>
#include <string>
#include <sstream>
#include <stdexcept>
#include <unordered_set>
class BST {
    struct Node { int key; std::unique_ptr<Node> left, right; explicit Node(int k):key(k){} };
    std::unique_ptr<Node> root;
    size_t count=0;
public:
    std::vector<int> path;
    ~BST(){clear();}
    bool insert(int k) {
        path.clear(); auto* link=&root;
        while (*link) { path.push_back((*link)->key); if(k==(*link)->key)return false;
            link=k<(*link)->key?&(*link)->left:&(*link)->right; }
        *link=std::make_unique<Node>(k); ++count; path.push_back(k); return true;
    }
    bool find(int k) {
        path.clear(); auto* n=root.get();
        while(n){path.push_back(n->key);if(k==n->key)return true;n=k<n->key?n->left.get():n->right.get();}return false;
    }
    bool erase(int k) {
        path.clear(); auto* link=&root;
        while(*link && (*link)->key!=k){path.push_back((*link)->key);link=k<(*link)->key?&(*link)->left:&(*link)->right;}
        if(!*link)return false;
        if(!(*link)->left) {auto next=std::move((*link)->right);*link=std::move(next);}
        else if(!(*link)->right){auto next=std::move((*link)->left);*link=std::move(next);}
        else {auto* successor=&(*link)->right;while((*successor)->left)successor=&(*successor)->left;
            (*link)->key=(*successor)->key;auto next=std::move((*successor)->right);*successor=std::move(next);}
        --count;return true;
    }
    void big_demo(int size) {
        if(size < 1) throw std::runtime_error("big_demo size must be positive");
        clear(); insert_range(1, size); path.clear();
    }
    void clear(){
        // Rotate away left children so destruction never recurses down a long chain.
        while(root){
            if(root->left){
                auto left=std::move(root->left);
                root->left=std::move(left->right);
                left->right=std::move(root); root=std::move(left);
            }else{auto right=std::move(root->right);root=std::move(right);}
        }
        count=0;path.clear();
    }
    std::vector<int> ordered()const {
        std::vector<int> out;std::vector<const Node*> stack;const Node* node=root.get();
        while(node || !stack.empty()){
            while(node){stack.push_back(node);node=node->left.get();}
            node=stack.back();stack.pop_back();out.push_back(node->key);node=node->right.get();
        }
        return out;
    }
    std::string snapshot(const std::string& status)const {
        std::ostringstream out;out<<"BST1 "<<count<<" "<<status<<"\n";
        struct Entry{const Node* node;const Node* parent;int depth;bool emit;};
        std::vector<Entry> stack;if(root)stack.push_back({root.get(),nullptr,0,false});
        std::unordered_set<int> highlighted(path.begin(),path.end());size_t rank=0;
        while(!stack.empty()){
            auto e=stack.back();stack.pop_back();
            if(e.emit){out<<e.node->key<<' '<<(e.parent?std::to_string(e.parent->key):"none")<<' '<<rank++<<' '<<e.depth<<' '<<(highlighted.count(e.node->key)?1:0)<<'\n';continue;}
            if(e.node->right)stack.push_back({e.node->right.get(),e.node,e.depth+1,false});
            stack.push_back({e.node,e.parent,e.depth,true});
            if(e.node->left)stack.push_back({e.node->left.get(),e.node,e.depth+1,false});
        }
        return out.str();
    }
private:
    void insert_range(int low, int high) {
        if(low > high) return;
        int middle = low + (high - low) / 2;
        insert(middle);
        if(low < middle) insert_range(low, middle - 1);
        if(middle < high) insert_range(middle + 1, high);
    }
};
