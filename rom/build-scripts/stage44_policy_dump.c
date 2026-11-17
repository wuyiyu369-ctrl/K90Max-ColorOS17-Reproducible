#include <sepol/policydb/policydb.h>
#include <sepol/kernel_to_cil.h>
#include <stdio.h>
int main(int argc,char **argv) {
    if(argc!=2) return 2;
    FILE *in=fopen(argv[1],"rb"); if(!in) return 3;
    policydb_t p; policy_file_t f;
    policy_file_init(&f);f.type=PF_USE_STDIO;f.fp=in;
    if(policydb_init(&p)||policydb_read(&p,&f,0)) return 4;
    fclose(in);
    int result=sepol_kernel_policydb_to_cil(stdout,&p);
    policydb_destroy(&p);return result;
}
