#ifndef _bb_h_
#define _bb_h_

#ifndef NULL
#define NULL ((void*)0)
#endif

#ifndef byte
typedef unsigned char byte;
#endif
#ifndef uint
typedef unsigned int uint;
#endif

typedef enum { false = 0, true = 1 } bool;

#define memSize 393216 // $60000 for M65 for now

#endif // _bb_h_
