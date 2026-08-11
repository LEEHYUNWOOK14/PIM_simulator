#include <cstdint>
#include <fstream>
#include <iomanip>
#include <cstring>
#include "half.h"
static half_float::half from_bits(uint16_t bits){half_float::half v;std::memcpy(&v,&bits,2);return v;}
static uint16_t to_bits(half_float::half v){uint16_t bits;std::memcpy(&bits,&v,2);return bits;}
int main(int argc,char**argv){
  if(argc!=2)return 2;
  std::ofstream out(argv[1]); uint32_t s=1;
  const uint16_t edge[]={0x0000,0x8000,0x0001,0x03ff,0x0400,0x3c00,0xbc00,0x7bff,0x7c00,0xfc00,0x7e00};
  for(auto a:edge)for(auto b:edge){half_float::half z=from_bits(a)*from_bits(b);
    out<<std::hex<<std::setw(4)<<std::setfill('0')<<a<<' '<<std::setw(4)<<b<<' '<<std::setw(4)<<to_bits(z)<<'\n';}
  for(int i=0;i<4096;i++){s^=s<<13;s^=s>>17;s^=s<<5;uint16_t a=s;s^=s<<13;s^=s>>17;s^=s<<5;uint16_t b=s;
    half_float::half z=from_bits(a)*from_bits(b);
    out<<std::hex<<std::setw(4)<<std::setfill('0')<<a<<' '<<std::setw(4)<<b<<' '<<std::setw(4)<<to_bits(z)<<'\n';}
}
