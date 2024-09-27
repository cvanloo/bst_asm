#pragma once

#include <unistd.h>
#include <stdint.h>
#include <assert.h>
#include <string.h>

typedef uint8_t U8;
typedef int8_t S8;
typedef uint16_t U16;
typedef int16_t S16;
typedef uint32_t U32;
typedef int32_t S32;
typedef uint64_t U64;
typedef int64_t S64;

#define KB(n) (((U64)(n)) << 10)
#define MB(n) (((U64)(n)) << 20)
#define GB(n) (((U64)(n)) << 30)
#define TB(n) (((U64)(n)) << 40)

U64 PAGE_SIZE = KB(4);

typedef struct Arena Arena;
struct Arena {
    U64 cap;
    U64 pos;
    U64 com;
    U64 align;
    U8 data[];
};

Arena *arena_make(U64 cap);
void arena_release(Arena *);
void arena_set_auto_align(Arena *, U64 align);
U64 arena_pos(Arena *);
void *arena_push_non_zero(Arena *, U64 size);
void *arena_push_aligned(Arena *, U64 size, U64 alignment);
void *arena_push(Arena *, U64 size);
void arena_pop_to(Arena *, U64 pos);
void arena_pop(Arena *, U64 size);
void arena_clear(Arena *);

#define push_array(arena, type, count) (type *) arena_push((arena), sizeof (type) * (count))
#define push_array_non_zero(arena, type, count) (type *) arena_push_non_zero((arena), sizeof (type) * (count))
#define push_struct(arena, type) (type *) arena_push((arena), sizeof (type))
#define push_struct_non_zero(arena, type) (type *) arena_push_non_zero((arena), sizeof (type))

#ifdef ARENA_IMPLEMENTATION

#include <sys/mman.h>

Arena *arena_make(U64 cap) {
    U64 off = cap % PAGE_SIZE;
    if (!off) cap += PAGE_SIZE - off;
    Arena *arena = mmap(0, cap, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(arena != MAP_FAILED && "mmap failed");
    int r = mprotect(arena, PAGE_SIZE, PROT_READ | PROT_WRITE);
    assert(r != -1 && "mprotect failed");
    arena->com = PAGE_SIZE;
    arena->cap = cap;
    arena->align = 1;
    return arena;
}

void arena_release(Arena *arena) {
    int r = munmap(arena, arena->cap);
    assert(r != -1 && "munmap failed");
}

void arena_set_auto_align(Arena *arena, U64 align) {
    if (align == 0) align = 1;
    arena->align = align;
}

U64 arena_pos(Arena *arena) {
    return arena->pos;
}

static inline
void *_arena_push(Arena *arena, U64 size, U64 alignment, U8 zero) {
    U64 align = arena->align;
    if (alignment) align = alignment;
    U64 off = arena->pos % align;
    if (off) off = align - off;
    U64 total_size = size + off;
    void *p = &arena->data[arena->pos];
    if (arena->pos + total_size > arena->com) {
        U64 off = (U64) p % PAGE_SIZE;
        void *pa = p + (PAGE_SIZE - off);
        U64 np = total_size / PAGE_SIZE;
        if ((total_size % PAGE_SIZE) != 0) np += 1;
        int r = mprotect(pa, np*PAGE_SIZE, PROT_READ | PROT_WRITE);
        assert(r != -1 && "mprotect failed");
        arena->com += np*PAGE_SIZE;
    }
    arena->pos += total_size;
    if (zero) memset(p, 0, total_size);
    return p + off;
}

void *arena_push_non_zero(Arena *arena, U64 size) {
    return _arena_push(arena, size, 0, 0);
}

void *arena_push_aligned(Arena *arena, U64 size, U64 alignment) {
    return _arena_push(arena, size, alignment, 1);
}

void *arena_push(Arena *arena, U64 size) {
    return _arena_push(arena, size, 0, 1);
}

static inline
void _arena_downsize(Arena *arena) {
    if ((arena->com - arena->pos) > (PAGE_SIZE << 2)) {
        U64 nrem = arena->com / PAGE_SIZE / 2;
        U64 rem = PAGE_SIZE * nrem;
        void *p = &arena->data[arena->com - sizeof (Arena) - rem];
        U64 off = (U64) p % PAGE_SIZE;
        assert(off == 0 && "p not page aligned");
        int r = mprotect(p, rem, PROT_NONE);
        assert(r != -1 && "mprotect failed");
        r = madvise(p, rem, MADV_DONTNEED | MADV_FREE); // ?
        assert(r != -1 && "madvice failed");
        arena->com -= rem;
    }
}

void arena_pop_to(Arena *arena, U64 pos) {
    assert(pos <= arena->pos && "pos out of range");
    arena->pos = pos;
    _arena_downsize(arena);
}

void arena_pop(Arena *arena, U64 size) {
    assert(size <= arena->pos && "size out of range");
    arena->pos -= size;
    _arena_downsize(arena);
}

void arena_clear(Arena *arena) {
    arena->pos = 0;
    _arena_downsize(arena);
}

#endif // ARENA_IMPLEMENTATION
