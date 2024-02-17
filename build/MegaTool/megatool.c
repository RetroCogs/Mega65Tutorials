#include "megatool.h"
#include "file.h"
#include "cruncher.h"
#include "imgconvert.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <limits.h>

uint GetAddressSizeInBytes(char* s)
{
	uint addresssize = strlen(s);
	uint addressbytesize = addresssize >> 1;
	return addressbytesize;
}

uint ReadAddress(char* s)
{
	uint address = 0;
	uint addresssize = strlen(s);
	// printf("size of address: %d\n", addresssize);
	for(int i = 0; i < addresssize; ++i)
	{
		byte c;
		if(s[i] >= '0' && s[i] <= '9') c = s[i] - '0';
		if(s[i] >= 'a' && s[i] <= 'f') c = s[i] - 'a' + 10;
		if(s[i] >= 'A' && s[i] <= 'F') c = s[i] - 'A' + 10;
		address *= 16;
		address += c;
	}

	return address;
}

int main(int argc, char * argv[])
{
	if((argc < 3) || (strcmp(argv[1], "-h") == 0) || (strcmp(argv[1], "--help") == 0))
	{
		printf("\n");
		printf("MEGATool usage:\n");
		printf("\n");
		printf("       ADD ADDRESS:     megatool -a <infile> <address>\n");
		printf("       APPEND FILES:    megatool -p <alignment xxxxxxxx> <infile1> [infile2] [infile3] [...] outfile\n");
		printf("       IFFL PACK:       megatool -i <infile1> [infile2] [infile3] [...] outfile\n");
		printf("       CRUNCH:          megatool -c [-[e|r] xxxxxxxx] <filename>> \n");
		printf("                                 -e: Make executable with start address xxxxxxxx.\n");
		printf("                                 -r: Relocate file to hex address xxxxxxxx.\n");
		printf("       IMAGE CONVERT:   megatool -x <infile1> outfile\n");
		printf("\n");
		return 0;
	}

	if(strcmp(argv[1], "-a") == 0) // add address
	{
		printf("\nMEGATOOL - ADD ADDRESS ------------------------------------------------------------\n\n");
		File myInFile;
		File myOutFile;

		if(!readFile(&myInFile, argv[2]))
		{
			printf("Error Opening file \"%s\", aborting.\n", argv[2]);
			return -1;
		}

		uint address = ReadAddress(argv[3]);
		uint addressbytesize = GetAddressSizeInBytes(argv[3]);
		uint totalsize = myInFile.size + addressbytesize;

		File *aTarget = &myOutFile;
		aTarget->size = totalsize;
		aTarget->data = (byte*)malloc(totalsize);
		byte* target = aTarget->data;

		for(int i=0; i<addressbytesize; i++)
		{
			target[i] = address & 0xff;
			address = address >> 8;
		}

		for(int j=0; j<myInFile.size; j++)
		{
			target[j+addressbytesize] = myInFile.data[j];
		}

		if(!writeFile(&myOutFile, argv[2], ".addr\0"))
		{
			printf("Error Writing file \"%s\", aborting.\n", myOutFile.name);
			return -1;
		}

		printf("MegaTool: wrote %s\n", myOutFile.name);

		freeFile(&myInFile);
		freeFile(&myOutFile);

		return 0;
	}





	else if(strcmp(argv[1], "-i") == 0) // IFFL pack
	{
		printf("\nMEGATOOL - IFFL PACK ------------------------------------------------------------\n\n");

		int numInFiles = argc-3;
		File* myInFiles = (File*)malloc(numInFiles * sizeof(File));
		File myOutFile;

		uint totalsize = 0;

		printf("Analyzing %d file sizes.\n", numInFiles);

		for(int i=0; i<numInFiles; i++)
		{
			char* filename = argv[i+2];
			if(!readFile(&myInFiles[i], filename))
			{
				printf("Error Opening file \"%s\", aborting.\n", filename);
				return -1;
			}
			printf("    %2d: %08X\n", i, myInFiles[i].size);
			totalsize += myInFiles[i].size - 4;
		}

		totalsize += 1 + 8 * numInFiles;

		File *aTarget = &myOutFile;
		aTarget->size = totalsize;
		aTarget->data = (byte*)malloc(totalsize);
		byte* target = aTarget->data;

		printf("Calculated total size: 0x%08X\n\n", totalsize);

		printf("Populating IFFL header.\n");

		totalsize = 0;

		// first write number of files into header
		target[totalsize] = numInFiles;

		totalsize++;

		// then write all start addresses and sizes into header
		for(int i=0; i<numInFiles; i++)
		{
			size_t filesize = myInFiles[i].size - 4;
			uint startaddress =	myInFiles[i].data[0] +
								(myInFiles[i].data[1] << 8) +
								(myInFiles[i].data[2] << 16) +
								(myInFiles[i].data[3] << 24);

			target[totalsize+0] = myInFiles[i].data[0];
			target[totalsize+1] = myInFiles[i].data[1];
			target[totalsize+2] = myInFiles[i].data[2];
			target[totalsize+3] = myInFiles[i].data[3];
			target[totalsize+4] = (filesize      ) & 0xff;
			target[totalsize+5] = (filesize >>  8) & 0xff;
			target[totalsize+6] = (filesize >> 16) & 0xff;
			target[totalsize+7] = (filesize >> 24) & 0xff;
			totalsize += 8;
			printf("    File %2d - StartAddress: 0x%08X, FileSize: 0x%08X \n", i, startaddress, filesize);
		}

		printf("Done writing IFFL header.\n\n");
		printf("Populating IFFL files.\n");

		for(int i=0; i<numInFiles; i++)
		{
			for(int j=0; j<myInFiles[i].size-4; j++)
			{
				target[totalsize+j] = myInFiles[i].data[j+4];
			}
			totalsize += myInFiles[i].size - 4;
			printf("    %2d: file written\n", i);
		}

		printf("Done populating IFFL files.\n\n");

		if(!writeFile(&myOutFile, argv[argc-1], "\0"))
		{
			printf("Error Writing file \"%s\", aborting.\n", myOutFile.name);
			return -1;
		}

		printf("MegaIFFL: wrote %s\n", myOutFile.name);

		for(int i = 0; i<numInFiles; i++)
		{
			freeFile(&myInFiles[i]);
		}

		freeFile(&myOutFile);

		return 0;		
	}





	else if(strcmp(argv[1], "-p") == 0) // append files with padding/alignment
	{
		printf("\nMEGATOOL - APPEND FILES ------------------------------------------------------------\n\n");

		int numInFiles = argc-4;
		File* myInFiles = (File*)malloc(numInFiles * sizeof(File));
		File myOutFile;
		uint alignsize = 0;

		uint totalsize = 0;

		printf("Analyzing %d file sizes.\n", numInFiles);

		alignsize = ReadAddress(argv[2]);
		printf("alignsize: 0x%08X\n", alignsize);

		for(int i=0; i<numInFiles; i++)
		{
			char* filename = argv[i+3];
			if(!readFile(&myInFiles[i], filename))
			{
				printf("Error Opening file \"%s\", aborting.\n", filename);
				return -1;
			}

			uint filesize = myInFiles[i].size;
			uint alignedfilesize = (filesize + alignsize - 1) & (UINT_MAX - (alignsize - 1));
			printf("    %2d: %08X %08X\n", i, filesize, alignedfilesize);

			totalsize += alignedfilesize;
		}

		File *aTarget = &myOutFile;
		aTarget->size = totalsize;
		aTarget->data = (byte*)malloc(totalsize);
		byte* target = aTarget->data;

		printf("Calculated total size: 0x%08X\n\n", totalsize);

		totalsize = 0;

		for(int i=0; i<numInFiles; i++)
		{
			uint filesize = myInFiles[i].size;
			uint alignedfilesize = (filesize + alignsize - 1) & (UINT_MAX - (alignsize - 1));
			uint paddingsize = alignedfilesize - filesize;

			for(int j=0; j<filesize; j++)
			{
				target[totalsize+j] = myInFiles[i].data[j];
			}

			totalsize += filesize;

			for(int j=0; j<paddingsize; j++)
			{
				target[totalsize+j] = 0;
			}

			totalsize += paddingsize;
			
			printf("    %2d: file written\n", i);
		}

		printf("Done appending files.\n\n");

		if(!writeFile(&myOutFile, argv[argc-1], "\0"))
		{
			printf("Error Writing file \"%s\", aborting.\n", myOutFile.name);
			return -1;
		}

		printf("append: wrote %s\n", myOutFile.name);

		for(int i = 0; i<numInFiles; i++)
		{
			freeFile(&myInFiles[i]);
		}

		freeFile(&myOutFile);

		return 0;		
	}





	else if(strcmp(argv[1], "-c") == 0) // crunch
	{
		printf("\nMEGATOOL - CRUNCH ------------------------------------------------------------\n\n");

		File myFile;
		File myMCFile;
		char* fileName;
		bool isExecutable = false;		
		bool isRelocated = false;
		uint address = 0;

		if(argc == 3)
		{
			fileName = argv[2];
		}
		else
		{
			int i;

			char *s = argv[3];
			fileName = argv[4];

			if(strcmp(argv[2], "-e") == 0)
			{
				isExecutable = true;
				// printf("Creating executable at $2001\n");
			}
			else if(strcmp(argv[2], "-r") == 0)
			{
				isRelocated = true;
				// printf("Relocating to:           0x%08X\n", address);
			}
			else
			{
				printf("Don't understand, aborting.\n");
				return -1;
			}

			address = ReadAddress(argv[3]);
			printf("address: 0x%08X\n", address);
		}

		if(!readFile(&myFile, fileName))
		{
			printf("Error Opening file \"%s\", aborting.\n", fileName);
			return -1;
		}

		if(!crunch(&myFile, &myMCFile, address, isExecutable, isRelocated))
		{
			freeFile(&myFile);
			return -1;
		}

		if(!writeFile(&myMCFile, myFile.name, ".mc\0"))
		{
			printf("Error Writing file \"%s\", aborting.\n", myMCFile.name);
			return -1;
		}

		printf("MegaCrunch: \"%s\" -> \"%s\"\n", myFile.name, myMCFile.name);

		freeFile(&myFile);
		freeFile(&myMCFile);

		return 0;
	}






	else if(strcmp(argv[1], "-x") == 0) // image convert
	{
		printf("\nMEGATOOL - IMAGE CONVERT ------------------------------------------------------------\n\n");

		File myFile;
		File myMIFile;
		char* fileName;
		char* outfileName;
		uint address = 0;

		fileName = argv[2];
		outfileName = argv[3];

		if(!readFile(&myFile, fileName))
		{
			printf("Error Opening file \"%s\", aborting.\n", fileName);
			return -1;
		}

		if(!imgconvert(&myFile, &myMIFile))
		{
			freeFile(&myFile);
			return -1;
		}

		if(!writeFileWithExtension(&myMIFile, outfileName))
		{
			printf("Error Writing file \"%s\", aborting.\n", myMIFile.name);
			return -1;
		}

		printf("MegaImageConvert: \"%s\" -> \"%s\"\n", myFile.name, myMIFile.name);

		freeFile(&myFile);
		freeFile(&myMIFile);

		return 0;
	}	
}
