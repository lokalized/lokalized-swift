/* Development-only positive control: the sanitizer must detect this race.
 * Outside the SwiftPM test target; never linked into Lokalized or consumers.
 */
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>

static atomic_int ready;
static volatile int unprotected;

static void *race(void *unused) {
    (void)unused;
    atomic_fetch_add_explicit(&ready, 1, memory_order_relaxed);
    while (atomic_load_explicit(&ready, memory_order_relaxed) != 2) {
        sched_yield();
    }
    for (int index = 0; index < 100000; index++) {
        unprotected++;
    }
    return 0;
}

int main(void) {
    pthread_t first, second;
    if (pthread_create(&first, 0, race, 0) != 0 ||
        pthread_create(&second, 0, race, 0) != 0) {
        return 2;
    }
    if (pthread_join(first, 0) != 0 || pthread_join(second, 0) != 0) {
        return 3;
    }
    return 0;
}
