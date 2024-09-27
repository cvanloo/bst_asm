#define ARENA_IMPLEMENTATION
#include "arena.h"
#include "binary_search_tree.h"

#include <string.h>

int main(int argc, char **argv) {
    PAGE_SIZE = getpagesize();
    Arena *arena = arena_make(16*KB(4));

    char *v1 = push_array(arena, char, 14);
    memcpy(v1, "Hello, World!", 14);

    BST *bst = bst_make(arena);
    bst_insert(bst, 5, v1);

    bst_clear(bst);
    arena_release(arena);
}
