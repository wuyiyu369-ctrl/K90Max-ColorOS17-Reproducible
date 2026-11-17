/* Minimal offline libsepol AV-rule editor. Preserves the exact Stage43
 * policy's types, constraints, transitions, policy version and permissive map.
 * Adds only an enumerated list of allows. No wildcard/permissive operation.
 */
#include <sepol/policydb/policydb.h>
#include <sepol/policydb/avtab.h>
#include <sepol/policydb/hashtab.h>
#include <sepol/policydb/ebitmap.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *s) { fprintf(stderr,"policy patch failed: %s\n",s); exit(1); }
static void rule(policydb_t *p,const char *s,const char *t,const char *c,const char *perms) {
    type_datum_t *sd=hashtab_search(p->p_types.table,s),*td=hashtab_search(p->p_types.table,t);
    class_datum_t *cd=hashtab_search(p->p_classes.table,c);
    if(!sd||!td||!cd) { fprintf(stderr,"missing %s %s %s\n",s,t,c); fail("symbol"); }
    avtab_key_t key={.source_type=sd->s.value,.target_type=td->s.value,.target_class=cd->s.value,.specified=AVTAB_ALLOWED};
    avtab_datum_t *datum=avtab_search(&p->te_avtab,&key), value={0};
    char buf[256]; snprintf(buf,sizeof(buf),"%s",perms); char *save=NULL;
    for(char *word=strtok_r(buf," ",&save);word;word=strtok_r(NULL," ",&save)) {
        perm_datum_t *pd=hashtab_search(cd->permissions.table,word);
        if(!pd&&cd->comdatum) pd=hashtab_search(cd->comdatum->permissions.table,word);
        if(!pd||pd->s.value>32) fail("permission");
        value.data |= 1U << (pd->s.value-1);
    }
    if(datum) datum->data|=value.data;
    else if(avtab_insert(&p->te_avtab,&key,&value)) fail("avtab_insert");
    printf("allow %s %s:%s { %s };\n",s,t,c,perms);
}
static void read_policy(policydb_t *p,const char *name) {
    FILE *f=fopen(name,"rb"); if(!f) fail("open input");
    policy_file_t pf; policy_file_init(&pf); pf.type=PF_USE_STDIO;pf.fp=f;
    if(policydb_init(p)||policydb_read(p,&pf,0)) fail("policydb_read");
    fclose(f);
}
static void client_attribute(policydb_t *p,const char *type,const char *attribute) {
    type_datum_t *td=hashtab_search(p->p_types.table,type);
    type_datum_t *ad=hashtab_search(p->p_types.table,attribute);
    if(!ad && !strcmp(attribute,"halclientdomain")) {
        puts("halclientdomain was expanded away by the original compiler; explicit narrow transport rules used");
        return;
    }
    if(!td||!ad||ad->flavor!=TYPE_ATTRIB) fail("client attribute missing");
    if(ebitmap_set_bit(&p->type_attr_map[td->s.value-1],ad->s.value-1,1)) fail("type map");
    if(p->attr_type_map && ebitmap_set_bit(&p->attr_type_map[ad->s.value-1],td->s.value-1,1)) fail("attribute map");
    printf("typeattribute %s %s;\n",type,attribute);
}
int main(int argc,char **argv) {
    if(argc!=3) fail("usage: input output");
    policydb_t p,q; read_policy(&p,argv[1]);
    printf("INPUT_POLICY version=%u types=%u classes=%u\n",p.policyvers,p.p_types.nprim,p.p_classes.nprim);
    client_attribute(&p,"vendor_touch_init_shell","hal_uniperf_client");
    client_attribute(&p,"vendor_touch_init_shell","halclientdomain");
    /* Accesses observed in logs, and the new native client's narrow transport. */
    rule(&p,"vendor_touch_init_shell","vendor_sysfs_xm_power","dir","getattr search open read");
    rule(&p,"vendor_touch_init_shell","vendor_sysfs_xm_power","file","getattr open read write");
    rule(&p,"vendor_touch_init_shell","sysfs_therm","dir","getattr search open read");
    rule(&p,"vendor_touch_init_shell","sysfs_therm","file","getattr open read write");
    rule(&p,"vendor_touch_init_shell","sysfs_battery_supply","dir","getattr search open read");
    rule(&p,"vendor_touch_init_shell","sysfs_battery_supply","file","getattr open read");
    rule(&p,"vendor_touch_init_shell","sysfs_batteryinfo","dir","getattr search open read");
    rule(&p,"vendor_touch_init_shell","sysfs_batteryinfo","file","getattr open read");
    rule(&p,"vendor_touch_init_shell","system_data_file","dir","getattr search");
    rule(&p,"vendor_touch_init_shell","system_data_file","file","getattr open read");
    rule(&p,"vendor_touch_init_shell","hal_uniperf_service","service_manager","find");
    rule(&p,"vendor_touch_init_shell","servicemanager","binder","call transfer");
    rule(&p,"vendor_touch_init_shell","hal_uniperf_default","binder","call transfer");
    rule(&p,"hal_uniperf_default","vendor_touch_init_shell","binder","transfer");
    /* The product V11 bridge publishes the Oplus charger AIDL under the
     * existing hal_power_service label. The exact service name is assigned
     * in product_service_contexts; this rule does not expose default services. */
    rule(&p,"vendor_touch_init_shell","hal_power_service","service_manager","add find");
    rule(&p,"vendor_touch_init_shell","system_server","binder","call transfer");
    rule(&p,"system_server","vendor_touch_init_shell","binder","call transfer");
    rule(&p,"vendor_init","proc_powerhal_cpu_ctrl","file","getattr setattr");
    rule(&p,"mtk_hal_power","proc_powerhal_cpu_ctrl","dir","getattr search open read");
    rule(&p,"mtk_hal_power","proc_powerhal_cpu_ctrl","file","getattr open read write");
    rule(&p,"system_server","sysfs_therm","file","getattr open write");
    rule(&p,"vendor_touch_init_shell","vendor_data_file","dir","getattr search open write add_name");
    rule(&p,"vendor_touch_init_shell","vendor_data_file","file","getattr create open read write append");
    FILE *f=fopen(argv[2],"wb");if(!f) fail("open output");
    policy_file_t pf; policy_file_init(&pf);pf.type=PF_USE_STDIO;pf.fp=f;
    if(policydb_write(&p,&pf)) fail("policydb_write");
    fclose(f);
    read_policy(&q,argv[2]);
    if(p.policyvers!=q.policyvers || p.p_types.nprim!=q.p_types.nprim || p.p_classes.nprim!=q.p_classes.nprim || !ebitmap_cmp(&p.permissive_map,&q.permissive_map)) fail("read-back metadata");
    printf("POLICY_READBACK_OK version=%u types=%u classes=%u\n",q.policyvers,q.p_types.nprim,q.p_classes.nprim);
    policydb_destroy(&q);policydb_destroy(&p);return 0;
}
