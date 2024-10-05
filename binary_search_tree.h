#pragma once

#include "arena.h"

typedef S64 (*Compare_Func)(void *self, void *other);

typedef struct Node Node;
struct Node {
    void *key;
    void *val;
    Node *left;
    Node *right;
};

typedef struct Entry Entry;
struct Entry {
    void *key;
    void *val;
};

typedef struct BST BST;
struct BST {
    U64 size;
    U64 height;
    Arena *arena;
    Node *root;
    Compare_Func key_cmp;
};

typedef struct Entries Entries;
struct Entries {
    U64 size;
    Entry **entries;
};

typedef void (*Entry_Callback)(Entry *);

extern BST *bst_make(Arena *, Compare_Func key_cmp);
extern void bst_clear(BST *);
extern Entry *bst_insert(BST *, void *key, void *value);
extern Entry *bst_find(BST *, void *key);
extern Entries bst_find_all(BST *, Arena *, void *key);
extern U64 bst_height(BST *);
extern U64 bst_size(BST *);
extern void bst_inorder(BST *, Entry_Callback cb);
extern Entry *bst_remove(BST *, void *key);
