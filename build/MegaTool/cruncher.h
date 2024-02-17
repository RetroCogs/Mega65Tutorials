#ifndef _cruncher_h_
#define _cruncher_h_

#include "megatool.h"
#include "file.h"

bool crunch(File *aSource, File *aTarget, uint startAdress, bool isExecutable, bool isRelocated);

#endif // _cruncher_h_
