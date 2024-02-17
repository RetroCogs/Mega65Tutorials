#ifndef _file_h_
#define _file_h_

#include "megatool.h"

#include <stdio.h>
#include <sys/stat.h>

typedef struct
{
	char *name;
	size_t size;
	byte *data;
} File;

void freeFile(File *aFile);
bool readFile(File *aFile, const char *fileName);
bool writeFile(File *aFile, const char *fileName, const char *extension);
bool writeFileWithExtension(File *aFile, const char *fileName);

#endif // _file_h_
