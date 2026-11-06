/* Exercise the APIs used by TeXShop against real engine-generated SyncTeX data. */
#ifdef TEST_LEGACY_PARSER
#include "synctex_parser_old.h"
#define SYNCTEX_VERSION_STRING "legacy"
#define synctex_scanner_p synctex_scanner_t
#define synctex_node_p synctex_node_t
#define synctex_scanner_next_result old_synctex_next_result
#define synctex_scanner_input old_synctex_scanner_input
#define synctex_node_sibling old_synctex_node_sibling
#define synctex_display_query(s, n, l, c, p) old_synctex_display_query(s, n, l, c)
#define synctex_scanner_new_with_output_file old_synctex_scanner_new_with_output_file
#define synctex_scanner_free old_synctex_scanner_free
#define synctex_edit_query old_synctex_edit_query
#define synctex_node_page old_synctex_node_page
#define synctex_node_box_visible_h old_synctex_node_box_visible_h
#define synctex_node_box_visible_width old_synctex_node_box_visible_width
#define synctex_node_box_visible_v old_synctex_node_box_visible_v
#define synctex_node_box_visible_height old_synctex_node_box_visible_height
#define synctex_scanner_get_name old_synctex_scanner_get_name
#define synctex_node_tag old_synctex_node_tag
#define synctex_node_line old_synctex_node_line
#else
#include "synctex_parser.h"
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

int main(int argc, char **argv) {
    assert(argc == 3 || argc == 5);
    assert(strcmp(zlibVersion(), "1.4") == 0);
    synctex_scanner_p scanner = synctex_scanner_new_with_output_file(argv[1], NULL, 1);
    if (argc == 3) {
        assert(strcmp(argv[2], "invalid") == 0);
        assert(scanner == NULL);
        return 0;
    }
    assert(scanner);
    int line = atoi(argv[3]), page = atoi(argv[4]);
    /* TeXShop resolves its document against the input records before querying. */
    const char *query_name = NULL;
    for (synctex_node_p input = synctex_scanner_input(scanner); input;
         input = synctex_node_sibling(input)) {
        const char *name = synctex_scanner_get_name(scanner, synctex_node_tag(input));
        if (name && strstr(name, argv[2])) { query_name = name; break; }
    }
    assert(query_name);
    assert(synctex_display_query(scanner, query_name, line, 0, page) > 0);
    synctex_node_p node;
    float x = 0, y = 0;
    int found = 0;
    while ((node = synctex_scanner_next_result(scanner))) {
        if (synctex_node_page(node) != page) continue;
        x = synctex_node_box_visible_h(node) + synctex_node_box_visible_width(node) / 2;
        y = synctex_node_box_visible_v(node) - synctex_node_box_visible_height(node) / 2;
        assert(isfinite(x) && isfinite(y));
        assert(x > 0 && y > 0);
        found = 1;
        break;
    }
    assert(found);
    assert(synctex_edit_query(scanner, page, x, y) > 0);
    found = 0;
    while ((node = synctex_scanner_next_result(scanner))) {
        const char *name = synctex_scanner_get_name(scanner, synctex_node_tag(node));
        if (name && strstr(name, argv[2]) && synctex_node_line(node) == line) found = 1;
    }
    assert(found);
    synctex_scanner_free(scanner);
    printf("PASS: %s, line %d, page %d (SyncTeX %s, zlib %s)\n",
           argv[1], line, page, SYNCTEX_VERSION_STRING, zlibVersion());
    return 0;
}
