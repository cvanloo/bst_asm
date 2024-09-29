#define ARENA_IMPLEMENTATION
#include "arena.h"
#include "binary_search_tree.h"

#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static void
print_entry(Entry *entry) {
    printf("%lu: %s\n", entry->key, (char *) entry->val);
}

typedef struct ArrayEntries ArrayEntries;
struct ArrayEntries {
    U64 size;
    U64 cap;
    Entry data[];
};

static Entry *
array_entries_push(ArrayEntries **entries) {
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
static void
collect_to_entries(Entry *entry) {
    if (collect_to_entries_result) {
        Entry* new = array_entries_push(collect_to_entries_result);
        new->key = entry->key;
        new->val = entry->val;
    }
}

#define TEST_ASSERT(exp) if (!(exp)) return 0;
U8 test_insert(Arena *);
U8 test_remove(Arena *);
U8 test_remove2(Arena *);
U8 test_remove3(Arena *);
U8 test_remove4(Arena *);
U8 test_remove5(Arena *);
U8 test_find_all(Arena *);

typedef U8 (*Test_Function)(Arena *);

static Test_Function TEST_FUNCTIONS[] = {
    test_insert,
    test_remove,
    test_remove2,
    test_remove3,
    test_remove4,
    test_remove5,
    test_find_all,
    0,
};

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

    U64 i = 0;
    for (Test_Function test = TEST_FUNCTIONS[i]; test != 0; test = TEST_FUNCTIONS[++i]) {
        arena_clear(arena);
        if (!test(arena)) {
            printf("TEST %lu FAILED", i);
        }
    }

    arena_release(arena);
}

U8
test_insert(Arena *arena) {
    BST *bst = bst_make(arena);
    bst_insert(bst, 2, 0);
    TEST_ASSERT(bst_size(bst) == 1);
    TEST_ASSERT(bst_height(bst) == 1);
    bst_insert(bst, 4, 0);
    TEST_ASSERT(bst_size(bst) == 2);
    TEST_ASSERT(bst_height(bst) == 2);
    bst_insert(bst, 1, 0);
    TEST_ASSERT(bst_size(bst) == 3);
    TEST_ASSERT(bst_height(bst) == 2);
    bst_insert(bst, 3, 0);
    TEST_ASSERT(bst_size(bst) == 4);
    TEST_ASSERT(bst_height(bst) == 3);
    return 1;
}

U8
test_remove(Arena *arena) {
    BST *bst = bst_make(arena);
    bst_insert(bst, 5, 0);
    bst_insert(bst, 9, 0);
    bst_insert(bst, 6, 0);
    bst_insert(bst, 2, 0);
    bst_insert(bst, 1, 0);
    bst_insert(bst, 3, 0);
    float first_seven = 7.1;
    float second_seven = 7.2;
    bst_insert(bst, 7, &first_seven);
    Entry *e1 = bst_insert(bst, 7, &second_seven);
    bst_insert(bst, 12, 0);
    TEST_ASSERT(bst_size(bst) == 9);
    TEST_ASSERT(bst_height(bst) == 5);
    Entry *r1 = bst_remove(bst, 7);
    TEST_ASSERT((float*)(r1->val) == &first_seven);
    TEST_ASSERT(bst_size(bst) == 8);
    //TEST_ASSERT(bst_height(bst) == 4);
    Entry *f1 = bst_find(bst, 7);
    TEST_ASSERT((float*)(f1->val) == &second_seven);
    bst_remove(bst, 6);
    TEST_ASSERT(bst_size(bst) == 7);
    //TEST_ASSERT(bst_height(bst) == 3);
    Node *f2 = (Node *) bst_find(bst, 9);
    TEST_ASSERT(f2->left == (Node *) e1);
    bst_remove(bst, 12);
    TEST_ASSERT(bst_size(bst) == 6);
    //TEST_ASSERT(bst_height(bst) == 3);
    bst_remove(bst, 9);
    TEST_ASSERT(bst_size(bst) == 5);
    //TEST_ASSERT(bst_height(bst) == 3);
    TEST_ASSERT(bst->root->right == (Node *) e1);
    bst_remove(bst, 5);
    TEST_ASSERT(bst->root == (Node *) e1);
    TEST_ASSERT(bst_size(bst) == 4);
    //TEST_ASSERT(bst_height(bst) == 3);
    return 1;
}

U8
test_remove2(Arena *arena) {
    BST *bst = bst_make(arena);
    Entry *root = bst_insert(bst, 5, 0);
    bst_insert(bst, 9, 0);
    bst_insert(bst, 6, 0);
    bst_insert(bst, 2, 0);
    bst_insert(bst, 1, 0);
    bst_insert(bst, 3, 0);
    float first_seven = 7.1;
    float second_seven = 7.2;
    bst_insert(bst, 7, &first_seven);
    Entry *e1 = bst_insert(bst, 7, &second_seven);
    bst_insert(bst, 12, 0);
    TEST_ASSERT(bst_size(bst) == 9);
    TEST_ASSERT(bst_height(bst) == 5);
    Entry *r1 = bst_remove(bst, 5);
    TEST_ASSERT(r1 == root);
    TEST_ASSERT(bst_size(bst) == 8);
    //TEST_ASSERT(bst_height(bst) == 4);
    return 1;
}

U8
test_remove3(Arena *arena) {
    BST *bst = bst_make(arena);
    bst_insert(bst, 5, 0);
    bst_insert(bst, 2, 0);
    bst_insert(bst, 1, 0);
    bst_insert(bst, 3, 0);
    bst_insert(bst, 12, 0);
    bst_insert(bst, 10, 0);
    bst_insert(bst, 37, 0);
    bst_insert(bst, 40, 0);
    bst_insert(bst, 16, 0);
    bst_insert(bst, 11, 0);
    bst_insert(bst, 8, 0);
    bst_insert(bst, 9, 0);
    bst_insert(bst, 7, 0);
    TEST_ASSERT(bst_size(bst) == 13);
    TEST_ASSERT(bst_height(bst) == 5);

    ArrayEntries *entries = malloc(sizeof(ArrayEntries));
    collect_to_entries_result = &entries;
    {
        bst_inorder(bst, &collect_to_entries);
        U64 expected[13] = {1, 2, 3, 5, 7, 8, 9, 10, 11, 12, 16, 37, 40};
        TEST_ASSERT(entries->size == 13);
        for (U64 i = 0; i < entries->size; ++i) {
            TEST_ASSERT(entries->data[i].key == expected[i]);
        }
    }

    bst_remove(bst, 5);
    TEST_ASSERT(bst_size(bst) == 12);
    TEST_ASSERT(bst_height(bst) == 5);

    entries->size = 0;
    {
        bst_inorder(bst, &collect_to_entries);
        U64 expected[12] = {1, 2, 3, 7, 8, 9, 10, 11, 12, 16, 37, 40};
        TEST_ASSERT(entries->size == 12);
        for (U64 i = 0; i < entries->size; ++i) {
            TEST_ASSERT(entries->data[i].key == expected[i]);
        }
    }

    return 1;
}

U8
test_remove4(Arena *arena) {
    BST *bst = bst_make(arena);
    bst_insert(bst, 5, 0);
    bst_insert(bst, 2, 0);
    bst_insert(bst, 1, 0);
    bst_insert(bst, 3, 0);
    bst_insert(bst, 12, 0);
    bst_insert(bst, 10, 0);
    bst_insert(bst, 37, 0);
    bst_insert(bst, 40, 0);
    bst_insert(bst, 16, 0);
    bst_insert(bst, 11, 0);
    bst_insert(bst, 8, 0);
    bst_insert(bst, 9, 0);
    bst_insert(bst, 7, 0);
    TEST_ASSERT(bst_size(bst) == 13);
    TEST_ASSERT(bst_height(bst) == 5);
    bst_remove(bst, 12);
    TEST_ASSERT(bst_size(bst) == 12);
    TEST_ASSERT(bst_height(bst) == 5);

    ArrayEntries *entries = malloc(sizeof(ArrayEntries));
    collect_to_entries_result = &entries;
    bst_inorder(bst, &collect_to_entries);
    U64 expected[12] = {1, 2, 3, 5, 7, 8, 9, 10, 11, 16, 37, 40};
    TEST_ASSERT(entries->size == 12);
    for (U64 i = 0; i < entries->size; ++i) {
        TEST_ASSERT(entries->data[i].key == expected[i]);
    }
    return 1;
}

U8
test_remove5(Arena *arena) {
    BST *bst = bst_make(arena);
    bst_insert(bst, 5, 0);
    bst_insert(bst, 2, 0);
    bst_insert(bst, 1, 0);
    bst_insert(bst, 3, 0);
    bst_insert(bst, 12, 0);
    bst_insert(bst, 10, 0);
    bst_insert(bst, 37, 0);
    bst_insert(bst, 40, 0);
    bst_insert(bst, 16, 0);
    bst_insert(bst, 11, 0);
    bst_insert(bst, 8, 0);
    bst_insert(bst, 9, 0);
    TEST_ASSERT(bst_size(bst) == 12);
    TEST_ASSERT(bst_height(bst) == 5);
    bst_remove(bst, 5);
    TEST_ASSERT(bst_size(bst) == 11);
    //TEST_ASSERT(bst_height(bst) == 4);

    ArrayEntries *entries = malloc(sizeof(ArrayEntries));
    collect_to_entries_result = &entries;
    bst_inorder(bst, &collect_to_entries);
    U64 expected[11] = {1, 2, 3, 8, 9, 10, 11, 12, 16, 37, 40};
    TEST_ASSERT(entries->size == 11);
    for (U64 i = 0; i < entries->size; ++i) {
        TEST_ASSERT(entries->data[i].key == expected[i]);
    }
    return 1;
}

U8
test_find_all(Arena *arena) {
    BST *bst = bst_make(arena);
    float two_one = 2.1;
    float two_two = 2.2;
    float two_three = 2.3;
    float seven_one = 7.1;
    float seven_two = 7.2;
    bst_insert(bst, 5, 0);
    bst_insert(bst, 2, &two_one);
    bst_insert(bst, 2, &two_two);
    bst_insert(bst, 3, 0);
    bst_insert(bst, 2, &two_three);
    bst_insert(bst, 7, &seven_one);
    bst_insert(bst, 8, 0);
    bst_insert(bst, 7, &seven_two);
    TEST_ASSERT(bst_size(bst) == 8);
    TEST_ASSERT(bst_height(bst) == 5);

    ArrayEntries *entries = malloc(sizeof(ArrayEntries));
    collect_to_entries_result = &entries;
    bst_inorder(bst, &collect_to_entries);
    U64 expected[8] = {2, 2, 2, 3, 5, 7, 7, 8};
    TEST_ASSERT(entries->size == 8);
    for (U64 i = 0; i < entries->size; ++i) {
        TEST_ASSERT(entries->data[i].key == expected[i]);
    }

    Entry *f1 = bst_find(bst, 2);
    TEST_ASSERT(f1 != 0);
    TEST_ASSERT((float *) f1->val == &two_one);

    Entry *f2 = bst_find(bst, 7);
    TEST_ASSERT(f2 != 0);
    TEST_ASSERT((float *) f2->val == &seven_one);

    Entries finds2 = bst_find_all(bst, arena, 2);
    TEST_ASSERT(finds2.size == 3);

    Entries finds7 = bst_find_all(bst, arena, 7);
    TEST_ASSERT(finds7.size == 2);

    return 1;
}
