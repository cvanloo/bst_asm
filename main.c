#define ARENA_IMPLEMENTATION
#include "arena.h"
#include "binary_search_tree.h"

#include <string.h>
#include <stdio.h>

int main(int argc, char **argv) {
    PAGE_SIZE = getpagesize();
    Arena *arena = arena_make(16*KB(4));

    char *v1 = push_array(arena, char, 14);
    memcpy(v1, "Hello, World!", 14);

    char *v2 = push_array(arena, char, 14);
    memcpy(v2, "Hello, Moon!!", 14);

    BST *bst = bst_make(arena);
    bst_insert(bst, 5, v1);
    bst_insert(bst, 1, v1);
    bst_insert(bst, 7, v1);
    Entry *e4 = bst_insert(bst, 7, v2);

    (void) e4;

    Entry *res1 = bst_find(bst, 8);
    assert(res1 == 0 && "found (but should be not found)");

    Entry *res2 = bst_find(bst, 7);
    assert(res2 && "not found (but should be found)");

    Entries finds = bst_find_all(bst, arena, 7);
    for (U64 i = 0; i < finds.size; ++i) {
        Entry *entry = finds.entries[i];
        printf("%s\n", (char *) entry->val);
    }

    bst_clear(bst);
    arena_release(arena);
}
