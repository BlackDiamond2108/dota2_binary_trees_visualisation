#include "bst.hpp"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <charconv>
#include <iostream>
#include <cerrno>
#include <cstring>
#include <algorithm>
#include <cctype>
int main(){
    int server=socket(AF_INET,SOCK_STREAM,0);int yes=1;setsockopt(server,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof yes);
    sockaddr_in addr{};addr.sin_family=AF_INET;addr.sin_port=htons(8765);inet_pton(AF_INET,"127.0.0.1",&addr.sin_addr);
    if(bind(server,(sockaddr*)&addr,sizeof addr)<0||listen(server,8)<0){std::cerr<<strerror(errno)<<'\n';return 1;}
    BST tree;std::cout<<"BST listening on http://127.0.0.1:8765\n"<<std::flush;
    while(true){int client=accept(server,nullptr,nullptr);if(client<0)continue;
        timeval timeout{2,0};setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof timeout);setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof timeout);
        std::string request;char buffer[2048];
        while(request.find("\r\n\r\n")==std::string::npos && request.size()<8192){auto n=recv(client,buffer,sizeof buffer,0);if(n<=0)break;request.append(buffer,n);}
        std::string body,status="200 OK";
        try{
            std::istringstream input(request);std::string method,url,version;input>>method>>url>>version;
            if(version.rfind("HTTP/1.",0)!=0 || (method!="GET" && method!="POST"))throw std::runtime_error("Expected HTTP GET or POST");
            if(method=="POST" && url!="/delete_many")throw std::runtime_error("Unknown POST endpoint");
            std::string message="ready";
            if(url=="/delete_many") {
                if(method!="POST")throw std::runtime_error("delete_many requires POST");
                auto headerEnd=request.find("\r\n\r\n");
                if(headerEnd==std::string::npos)throw std::runtime_error("Incomplete headers");
                std::string headers=request.substr(0,headerEnd);
                std::transform(headers.begin(),headers.end(),headers.begin(),[](unsigned char c){return std::tolower(c);});
                auto lengthAt=headers.find("\r\ncontent-length:");
                if(lengthAt==std::string::npos)throw std::runtime_error("Content-Length required");
                lengthAt+=17;while(lengthAt<headers.size() && headers[lengthAt]==' ')++lengthAt;
                size_t length=0;auto [lengthEnd,lengthError]=std::from_chars(headers.data()+lengthAt,headers.data()+headers.size(),length);
                if(lengthError!=std::errc() || lengthEnd==headers.data()+lengthAt || length>64*1024*1024)throw std::runtime_error("Invalid body length");
                const size_t offset=headerEnd+4;
                while(request.size()-offset<length){auto n=recv(client,buffer,sizeof buffer,0);if(n<=0)throw std::runtime_error("Incomplete body");request.append(buffer,n);}
                std::istringstream values(request.substr(offset,length));std::string token;std::vector<int> keys;
                while(values>>token){int key;auto [end,ec]=std::from_chars(token.data(),token.data()+token.size(),key);
                    if(ec!=std::errc() || end!=token.data()+token.size())throw std::runtime_error("Invalid batch key");
                    keys.push_back(key);
                }
                if(keys.empty())throw std::runtime_error("Empty batch");
                size_t removed=0;for(int key:keys)if(tree.erase(key))++removed;
                tree.path.clear();message="deleted_batch";
                std::cout<<"batch keys="<<keys.size()<<" removed="<<removed<<std::endl;
            }
            else if(url=="/clear") {tree.clear();message="cleared";}
            else if(url=="/demo") {tree.clear();for(int k:{50,30,70,20,40,60,80})tree.insert(k);tree.path.clear();message="demo";}
            else if(url!="/state"){
                auto slash=url.find('/',1);if(slash==std::string::npos)throw std::runtime_error("Unknown endpoint");
                auto op=url.substr(1,slash-1),value=url.substr(slash+1);int k;
                auto [end,ec]=std::from_chars(value.data(),value.data()+value.size(),k);
                if(ec!=std::errc()||end!=value.data()+value.size())throw std::runtime_error("Expected int32 key");
                if(op=="big_demo") {tree.big_demo(k);message="big_demo";}
                else if(op=="insert")message=tree.insert(k)?"inserted":"duplicate";
                else if(op=="delete")message=tree.erase(k)?"deleted":"not_found";
                else if(op=="find")message=tree.find(k)?"found":"not_found";
                else throw std::runtime_error("Unknown operation");
            }
            body=tree.snapshot(message);std::cout<<url<<" -> "<<message<<std::endl;
        }catch(const std::exception& e){status="400 Bad Request";body=e.what();}
        std::string response="HTTP/1.1 "+status+"\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+std::to_string(body.size())+"\r\n\r\n"+body;
        size_t sent=0;while(sent<response.size()){auto n=send(client,response.data()+sent,response.size()-sent,MSG_NOSIGNAL);if(n<=0)break;sent+=n;}close(client);
    }
}
