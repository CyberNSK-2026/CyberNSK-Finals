#include "webfinger.h"
#include <string.h>

json_t *build_jrd_response(Identity *id, const char *rel_filter) {
    json_t *jrd = json_object();

    json_object_set_new(jrd, "subject", json_string(id->subject));

    
    json_t *aliases = json_array();
    for (int i = 0; i < id->alias_count; i++) {
        json_array_append_new(aliases, json_string(id->aliases[i]));
    }
    json_object_set_new(jrd, "aliases", aliases);

    
    json_t *props = json_object();
    ProfileProperty *p = id->properties;
    while (p) {
        json_object_set_new(props, p->key, json_string(p->value));
        p = p->next;
    }
    json_object_set_new(jrd, "properties", props);

    
    json_t *links = json_array();
    ProfileLink *l = id->links;
    while (l) {
        if (rel_filter == NULL || strcmp(l->rel, rel_filter) == 0) {
            json_t *link_obj = json_object();
            json_object_set_new(link_obj, "rel", json_string(l->rel));
            json_object_set_new(link_obj, "href", json_string(l->href));
            if (l->type[0] != '\0') {
                json_object_set_new(link_obj, "type", json_string(l->type));
            }
            json_array_append_new(links, link_obj);
        }
        l = l->next;
    }
    json_object_set_new(jrd, "links", links);

    return jrd;
}
