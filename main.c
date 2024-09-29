#define ARENA_IMPLEMENTATION
#include "arena.h"
#include "binary_search_tree.h"

#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static 
void print_entry(Entry *entry) {
    printf("%lu: %s\n", entry->key, (char *) entry->val);
}

typedef struct ArrayEntries ArrayEntries;
struct ArrayEntries {
    U64 size;
    U64 cap;
    Entry data[];
};

static
Entry *array_entries_push(ArrayEntries **entries) {
    ArrayEntries *this = *entries;
    if (this->size >= this->cap) {
        if (this->cap == 0) {
            this->cap = 16;
        } else {
            this->cap = this->cap << 1;
        }
        this = realloc(this, sizeof(ArrayEntries) + sizeof(Entry) * this->cap);
        assert(this);
    }
    Entry *new = &this->data[this->size];
    this->size = this->size + 1;
    *entries = this;
    return new;
}

static ArrayEntries** collect_to_entries_result;
static
void collect_to_entries(Entry *entry) {
    if (collect_to_entries_result) {
        Entry* new = array_entries_push(collect_to_entries_result);
        new->key = entry->key;
        new->val = entry->val;
    }
}

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
    U64 h = bst_height(bst); // expected: 2
    U64 s = bst_size(bst);   // expected: 3
    Entry *e4 = bst_insert(bst, 7, v2);
    (void) e4;

    h = bst_height(bst); // expected: 3
    s = bst_size(bst);   // expected: 4

    Entry *res1 = bst_find(bst, 8);
    assert(res1 == 0 && "found (but should be not found)");

    Entry *res2 = bst_find(bst, 7);
    assert(res2 && "not found (but should be found)");

    Entries finds = bst_find_all(bst, arena, 7);
    for (U64 i = 0; i < finds.size; ++i) {
        Entry *entry = finds.entries[i];
        printf("%s\n", (char *) entry->val);
    }

    bst_inorder(bst, &print_entry);

    ArrayEntries *entries = malloc(sizeof(ArrayEntries));
    collect_to_entries_result = &entries;
    bst_inorder(bst, &collect_to_entries);
    for (U64 i = 0; i < entries->size; ++i) {
        Entry entry = entries->data[i];
        printf("-> %lu: %s\n", entry.key, (char *) entry.val);
    }

    Entry *not_found = bst_remove(bst, 8);
    assert(not_found == 0 && "found (but should be not found)");
    Entry *found = bst_remove(bst, 1);
    assert(found && "not found (but should be found)");
    //Entry *found2 = bst_remove(bst, 5);
    Entry *found2 = bst_remove(bst, 7);
    assert(found2 && "not found (2) (but should be found)");

    bst_clear(bst);
    arena_release(arena);
}
