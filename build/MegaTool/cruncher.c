#include "cruncher.h"
#include <stdio.h>
#include <stdlib.h>

#define log(format, ...)

#define NUM_BITS_SHORT_0	3
#define NUM_BITS_SHORT_1	6
#define NUM_BITS_SHORT_2	8
#define NUM_BITS_SHORT_3	10
#define NUM_BITS_LONG_0		4
#define NUM_BITS_LONG_1		7
#define NUM_BITS_LONG_2		10
#define NUM_BITS_LONG_3		13

#define LEN_SHORT_0			(1 << NUM_BITS_SHORT_0)
#define LEN_SHORT_1			(1 << NUM_BITS_SHORT_1)
#define LEN_SHORT_2			(1 << NUM_BITS_SHORT_2)
#define LEN_SHORT_3			(1 << NUM_BITS_SHORT_3)
#define LEN_LONG_0			(1 << NUM_BITS_LONG_0)
#define LEN_LONG_1			(1 << NUM_BITS_LONG_1)
#define LEN_LONG_2			(1 << NUM_BITS_LONG_2)
#define LEN_LONG_3			(1 << NUM_BITS_LONG_3)

#define COND_SHORT_0(o)		((o) >= 0 && (o) < LEN_SHORT_0)
#define COND_SHORT_1(o)		((o) >= LEN_SHORT_0 && (o) < LEN_SHORT_1)
#define COND_SHORT_2(o)		((o) >= LEN_SHORT_1 && (o) < LEN_SHORT_2)
#define COND_SHORT_3(o)		((o) >= LEN_SHORT_2 && (o) < LEN_SHORT_3)
#define COND_LONG_0(o)		((o) >= 0 && (o) < LEN_LONG_0)
#define COND_LONG_1(o)		((o) >= LEN_LONG_0 && (o) < LEN_LONG_1)
#define COND_LONG_2(o)		((o) >= LEN_LONG_1 && (o) < LEN_LONG_2)
#define COND_LONG_3(o)		((o) >= LEN_LONG_2 && (o) < LEN_LONG_3)

#define MAX_OFFSET			LEN_LONG_3
#define MAX_OFFSET_SHORT	LEN_SHORT_3

#include "DecrZero.h"

byte		*ibuf;
byte		*obuf;
uint		ibufSize;
int			get;	// points to ibuf[]
uint		put;	// points to obuf[]

typedef struct
{
	uint cost;
	uint next;
	uint litLen;
	uint offset;
} node;

typedef struct
{
	byte value;
	byte valueAfter;
	uint length;
} RLEInfo;

node		*context;
uint		*link;
RLEInfo		*rleInfo;
uint		first[65536];
uint		last[65536];

byte		curByte;
byte		curCnt;
uint		curIndex;

void wbit(uint bit)
{
	// printf("writing bit: %d\n", bit & 1);

	if(curCnt == 0)
	{
		obuf[curIndex] = curByte;
		curIndex = put;
		curCnt = 8;
		curByte = 0;
		put++;
	}

	curByte <<= 1;
	curByte |= (bit & 1);
	curCnt--;
}

void wflush()
{
	while(curCnt != 0)
	{
		curByte <<= 1;
		curCnt--;
	}
	obuf[curIndex] = curByte;
}

void wbyte(uint b)
{
  obuf[put] = b;
  put++;
}

void wbytes(uint get, uint len)
{
	uint i;
	for(i = 0; i < len; i++)
	{
		wbyte(ibuf[get]);
		get++;
	}
}

void wlength(uint len)
{
	//  if(len == 0) return; // Should never happen

	byte bit = 0x80;
	while((len & bit) == 0)
	{
		bit >>= 1;
	}

	while(bit > 1)
	{
		wbit(1);
		bit >>= 1;
		wbit(((len & bit) == 0) ? 0 : 1);
	}

	if(len < 0x80)
	{
		wbit(0);
	}
}

void woffset(uint offset, uint len)
{
	uint i = 0;
	uint n = 0;
	uint b;

	if(len == 1)
	{
		if(COND_SHORT_0(offset))
		{
			i = 0;
			n = NUM_BITS_SHORT_0;
		}
		if(COND_SHORT_1(offset))
		{
			i = 1;
			n = NUM_BITS_SHORT_1;
		}
		if(COND_SHORT_2(offset))
		{
			i = 2;
			n = NUM_BITS_SHORT_2;
		}
		if(COND_SHORT_3(offset))
		{
			i = 3;
			n = NUM_BITS_SHORT_3;
		}
	}
	else
	{
		if(COND_LONG_0(offset))
		{
			i = 0;
			n = NUM_BITS_LONG_0;
		}
		if(COND_LONG_1(offset))
		{
			i = 1;
			n = NUM_BITS_LONG_1;
		}
		if(COND_LONG_2(offset))
		{
			i = 2;
			n = NUM_BITS_LONG_2;
		}
		if(COND_LONG_3(offset))
		{
			i = 3;
			n = NUM_BITS_LONG_3;
		}
	}

	// First write number of bits
	wbit(((i & 2) == 0) ? 0 : 1);
	wbit(((i & 1) == 0) ? 0 : 1);

	if(n >= 8) // Offset is 2 bytes
	{
		// Then write the bits less than 8
		b = 1 << n;
		while(b > 0x100)
		{
			b >>= 1;
			wbit(((b & offset) == 0) ? 0 : 1);
		};

		// Finally write a whole byte, if necessary
		wbyte(offset & 255 ^ 255); // Inverted(!)
		offset >>= 8;
	}
	else // Offset is 1 byte
	{
		// Then write the bits less than 8
		b = 1 << n;
		while(b > 1)
		{
			b >>= 1;
			wbit(((b & offset) == 0) ? 1 : 0); // Inverted(!)
		};
	}
}

uint costOfLength(uint len)
{
	if(len ==   1)					return 1;
	if(len >=   2 && len <=   3)	return 3;
	if(len >=   4 && len <=   7)	return 5;
	if(len >=   8 && len <=  15)	return 7;
	if(len >=  16 && len <=  31)	return 9;
	if(len >=  32 && len <=  63)	return 11;
	if(len >=  64 && len <= 127)	return 13;
	if(len >= 128 && len <= 255)	return 14;

	printf("costOfLength got wrong value: %i\n", len);
	return 10000;
}

uint costOfOffset(uint offset, uint len)
{
	if(len == 1)
	{
		if(COND_SHORT_0(offset)) return NUM_BITS_SHORT_0;
		if(COND_SHORT_1(offset)) return NUM_BITS_SHORT_1;
		if(COND_SHORT_2(offset)) return NUM_BITS_SHORT_2;
		if(COND_SHORT_3(offset)) return NUM_BITS_SHORT_3;
	}
	else
	{
		if(COND_LONG_0(offset)) return NUM_BITS_LONG_0;
		if(COND_LONG_1(offset)) return NUM_BITS_LONG_1;
		if(COND_LONG_2(offset)) return NUM_BITS_LONG_2;
		if(COND_LONG_3(offset)) return NUM_BITS_LONG_3;
	}

	printf("costOfOffset got wrong offset: %i\n", offset);
	return 10000;
}

uint calculateCostOfMatch(uint len, uint offset)
{
	uint cost = 1; // Copy-bit
	cost += costOfLength(len - 1);
	cost += 2; // NumOffsetBits
	cost += costOfOffset(offset - 1, len - 1);
	return cost;
}

uint calculateCostOfLiteral(uint oldCost, uint litLen)
{
	uint newCost = oldCost + 8;

	// Quick wins on short matches are prioritized before a longer literal run,
	// which in the end results in a worse result. Most obvious on files hard to crunch.
	switch(litLen)
	{
		case 1:
		case 128:
			newCost++;
			break;
		case 2:
		case 4:
		case 8:
		case 16:
		case 32:
		case 64:
			newCost += 2;
			break;
		default:
			break;
	}

	return newCost;
}

void setupHelpStructures()
{
	uint i;

	// Setup RLE-info
	get = ibufSize - 1;
	while(get > 0)
	{
		byte cur = ibuf[get];
		if(cur == ibuf[get-1])
		{
			uint len = 2;
			while ((get >= len) && (cur == ibuf[get-len]))
			{
				len++;
			}

			rleInfo[get].length = len;
			if(get >= len)
			{
				rleInfo[get].valueAfter = ibuf[get-len];
			}
			else
			{
				rleInfo[get].valueAfter = cur; // Avoid accessing ibuf[-1]
			}

			get -= len;
		}
		else
		{
			get--;
		}
	}

	// Setup Linked list
	for(i = 0; i < 65536; i++)
	{
		first[i] = 0;
		last[i] = 0;
	}

	get = ibufSize - 1;
	uint cur = ibuf[get];

	while(get > 0)
	{
		cur = ((cur << 8) | ibuf[get-1]) & 65535;

		if(first[cur] == 0)
		{
			first[cur] = last[cur] = get;
		}
		else
		{
			link[last[cur]] = get;
			last[cur] = get;
		}

		if(rleInfo[get].length == 0) // No RLE-match here..
		{
			get--;
		}
		else // if RLE-match..
		{
			get -= (rleInfo[get].length - 1);
		}
	}
}

void findMatches()
{
	typedef struct match
	{
		uint length;
		uint offset;
	} match;

	match matches[256];

	node lastNode;
	uint i;

	get = ibufSize - 1;
	uint cur = ibuf[get];

	lastNode.cost = 0;
	lastNode.next = 0;
	lastNode.litLen = 0;

	while (get >= 0)
	{
		// Clear matches for current position
		for (i = 0; i < 256; i++)
		{
			matches[i].length = 0;
			matches[i].offset = 0;
		}

		cur = (cur << 8) & 65535; // Table65536 lookup
		if (get > 0) cur |= ibuf[get-1];
		int scn = first[cur];
		scn = link[scn];

		uint longestMatch = 0;

		if (rleInfo[get].length == 0) // No RLE-match here..
		{
			// Scan until start of file, or max offset
			while (((get - scn) <= MAX_OFFSET) && (scn > 0) && (longestMatch < 255))
			{
				// we have a match of length 2 or longer, but max 255 or file start
				uint len = 2;
				while ((len < 255) && (scn >= len) && (ibuf[scn - len] == ibuf[get - len]))
				{
					++len;
				}

				// Calc offset
				uint offset = get - scn;

				// Store match only if it's the longest so far
				if(len > longestMatch)
				{
					longestMatch = len;

					// Store the match only if first (= best) of this length
					while(len >= 2 && matches[len].length == 0)
					{
						// If len == 2, check against short offset!!
						if ((len > 2) || ((len == 2) && (offset <= MAX_OFFSET_SHORT)))
						{
							matches[len].length = len;
							matches[len].offset = get - scn;
						}

						len--;
					};
				}

				scn = link[scn]; // Table65535 lookup
	  		};

			first[cur] = link[first[cur]]; // Waste first entry

		}
		else // if RLE-match..
		{
			uint rleLen = rleInfo[get].length;
			byte rleValAfter = rleInfo[get].valueAfter;

			// First match with self-RLE, which is always one byte shorter than the RLE itself.
			uint len = rleLen - 1;
			if (len > 1)
			{
				if (len > 255) len = 255;
				longestMatch = len;

				// Store the match
				while(len >= 2)
				{
					matches[len].length = len;
					matches[len].offset = 1;

					len--;
				};
			}

			// Search for more RLE-matches..
			// Scan until start of file, or max offset
			while (((get - scn) <= MAX_OFFSET) && (scn > 0) && (longestMatch < 255))
			{
				// Check for longer matches with same value and after..
				if ((rleInfo[scn].length > longestMatch) && (rleLen > longestMatch))
				{
					uint offset = get - scn;
					len = rleInfo[scn].length;

					if (len > rleLen)
						len = rleLen;

					if ((len > 2) || ((len == 2) && (offset <= MAX_OFFSET_SHORT)))
					{
						matches[len].length = len;
						matches[len].offset = offset;

						longestMatch = len;
					}
				}

				// Check for matches beyond the RLE..
				if ((rleInfo[scn].length >= rleLen) && (rleInfo[scn].valueAfter == rleValAfter))
				{
					// Here is a match that goes beyond the RLE..
					// Find out correct offset to use valueAfter..
					// Then search further to see if more bytes equal.

					len = rleLen;
					uint offset = get - scn + (rleInfo[scn].length - rleLen);

					if (offset <= MAX_OFFSET)
					{
						while ((len < 255) && (get >= (offset + len)) && (ibuf[get - (offset + len)] == ibuf[get - len]))
						{
							++len;
						}

						if (len > longestMatch)
						{
							longestMatch = len;

							// Store the match only if first (= best) of this length
							while(len >= 2 && matches[len].length == 0)
							{
								// If len == 2, check against short offset!!
								if ((len > 2) || ((len == 2) && (offset <= MAX_OFFSET_SHORT)))
								{
									matches[len].length = len;
									matches[len].offset = offset;
								}

								len--;
							}; //while
						}
					}
				}

				scn = link[scn]; // Table65535 lookup
			}

	  
			if (rleInfo[get].length > 2)
			{
				// Expand RLE to next position
				rleInfo[get-1].length = rleInfo[get].length - 1;
				rleInfo[get-1].value = rleInfo[get].value;
				rleInfo[get-1].valueAfter = rleInfo[get].valueAfter;
			}
			else
			{
				// End of RLE, advance link.
				first[cur] = link[first[cur]]; // Waste first entry
			}
		}

		// Now we have all matches from this position..
		// ..visit all nodes reached by the matches.

		for (i = 255; i > 0; i--)
		{
			// Find all matches we stored
			uint len = matches[i].length;
			uint offset = matches[i].offset;

			if (len != 0)
			{
				uint targetI = get - len + 1;
				node* target = &context[targetI];

				// Calculate cost for this jump
				uint currentCost = lastNode.cost;
				currentCost += calculateCostOfMatch(len, offset);

				// If this match is first or cheapest way to get here
				// then update node
				if (target->cost == 0 || target->cost > currentCost)
				{
					target->cost = currentCost;
		  			target->next = get + 1;
		  			target->litLen = 0;
	  				target->offset = offset;
				}
	  		}
		}

		// Calc the cost for this node if using one more literal
		uint litLen = lastNode.litLen + 1;
		uint litCost = calculateCostOfLiteral(lastNode.cost, litLen);

		// If literal run is first or cheapest way to get here
		// then update node
		node* this = &context[get];
		if (this->cost == 0 || this->cost >= litCost)
		{
			this->cost = litCost;
			this->next = get + 1;
			this->litLen = litLen;
		}

		lastNode.cost = this->cost;
		lastNode.next = this->next;
		lastNode.litLen = this->litLen;

		// Loop to the next position
		get--;
	};
}

// Returns margin
int writeOutput()
{
	uint i;

	put = 0;
	curByte = 0;
	curCnt = 8;
	curIndex = put;
	put++;

	int maxDiff = 0;
	bool needCopyBit = true;

	for (i = 0; i < ibufSize;)
	{
		uint link = context[i].next;
		uint cost = context[i].cost;
		uint litLen = context[i].litLen;
		uint offset = context[i].offset;

		if (litLen == 0)
		{
			// Put Match
			uint len = link - i;

			// printf("$%06x -> $%06x: Mat(offset = %i, length = %i, %c)\n", curIndex, i, -offset, len, needCopyBit ? 'T' : 'F');
  
			if(needCopyBit)
			{
				wbit(1);
			}
			wlength(len - 1);
			woffset(offset - 1, len - 1);

			i = link;

			needCopyBit = true;
		}
		else
		{
			// Put LiteralRun
			needCopyBit = false;

			while(litLen > 0)
			{
				uint len = litLen < 255 ? litLen : 255;

				// printf("$%06x -> $%06x: Lit(length = %i, %c)\n", curIndex, i, len, litLen == 255 ? 'T' : 'F');

				wbit(0);
				wlength(len);
				wbytes(i, len);

				if (litLen == 255)
				{
					needCopyBit = true;
				}

				litLen -= len;
				i += len;
			};
		}

		if ((int)(i - put) > maxDiff)
		{
			maxDiff = i - put;
		}
	}

	// printf("$%06x - Writing length FF\n", curIndex);
	
	wbit(1);
	wlength(0xff);
	wflush();

	int margin = (maxDiff - (i - put));

	return margin;
}

bool crunch(File *aSource, File *aTarget, uint address, bool isExecutable, bool isRelocated)
{
	uint i;
	byte *target;

	ibufSize = aSource->size - 4;
	ibuf     =    (byte*)malloc(ibufSize                  );
	context  =    (node*)malloc(ibufSize * sizeof(node)   );
	link     =    (uint*)malloc(ibufSize * sizeof(uint)   );
	rleInfo  = (RLEInfo*)malloc(ibufSize * sizeof(RLEInfo));

	// Load ibuf and clear context
	for(i = 0; i < ibufSize; ++i)
	{
		ibuf[i] = aSource->data[i + 4];
		context[i].cost = 0;
		link[i] = 0;
		rleInfo[i].length = 0;
	}

	setupHelpStructures();
	findMatches();

	obuf = (byte*)malloc(memSize);
	int margin = writeOutput();

	printf("Margin:                  0x%08X\n", margin);

	uint packLen = put;
	uint fileLen = put;
	uint decrLen = 0;

	printf("packLen = 0x%08X\n", packLen);

	if(isExecutable)
	{
		decrLen = decruncherlength;
		fileLen += decrLen + 4;
		printf("decrLen = 0x%08X\n", decrLen);
	}
	else
	{
		fileLen += 8;
	}

	printf("fileLen = 0x%08X\n", fileLen);

	aTarget->size = fileLen;
	aTarget->data = (byte*)malloc(aTarget->size);
	target = aTarget->data;

	if(isExecutable)
	{
		// uint startAddress = 0x10000 - packLen;
		// uint transfAddress = fileLen + 0x2001 - 0x0101;

		uint transferfrom = 0x2001 + decruncherlength;
		uint transferto = 0x60000 - packLen - 1;

		printf("transferfrom = 0x%08X\n", transferfrom);
		printf("transferto = 0x%08X\n", transferto);
		printf("asm_dc_dst = 0x%08X\n", aSource->data[1] * 256 + aSource->data[0]);
		printf("decrunchinitlength = 0x%08X\n", decrunchinitlength);

		decrCode[asm_dc_transferlen  - 0x1800       +  0] = packLen        &  0xff;
		decrCode[asm_dc_transferlen  - 0x1800       +  1] = packLen        >> 8;

		decrCode[asm_dc_transferfrom - 0x1800       +  0] = transferfrom   &  0xff;
		decrCode[asm_dc_transferfrom - 0x1800       +  1] = transferfrom   >> 8;
		decrCode[asm_dc_transferfrom - 0x1800       +  2] = transferfrom   >> 16;

		decrCode[asm_dc_transferto   - 0x1800       +  0] = transferto     &  0xff;
		decrCode[asm_dc_transferto   - 0x1800       +  1] = transferto     >> 8;
		decrCode[asm_dc_transferto   - 0x1800       +  2] = transferto     >> 16;

		decrCode[asm_dc_depackfrom   - 0x1800       +  1] = transferto     &  0xff;
		decrCode[asm_dc_depackfrom   - 0x1800       +  5] = transferto     >> 8;
		decrCode[asm_dc_depackfrom   - 0x1800       +  9] = transferto     >> 16;
		decrCode[asm_dc_depackfrom   - 0x1800       + 13] = transferto     >> 24;

		decrCode[decrunchinitlength + asm_dc_lsrc   +  0] = transferto &  0xff;
		decrCode[decrunchinitlength + asm_dc_lsrc   +  1] = transferto >> 8;
		decrCode[decrunchinitlength + asm_dc_lsrc   +  2] = transferto >> 16;

		decrCode[decrunchinitlength + asm_dc_ldst   +  0] = aSource->data[0];
		decrCode[decrunchinitlength + asm_dc_ldst   +  1] = aSource->data[1];
		decrCode[decrunchinitlength + asm_dc_ldst   +  2] = 0;

		decrCode[decrunchinitlength + asm_dc_mdst   +  0] = aSource->data[0];
		decrCode[decrunchinitlength + asm_dc_mdst   +  1] = aSource->data[1];
		decrCode[decrunchinitlength + asm_dc_mdst   +  2] = 0;

		decrCode[decrunchinitlength + asm_dc_jumpto +  1] = address      &  0xff;
		decrCode[decrunchinitlength + asm_dc_jumpto +  2] = address      >> 8;

		target[0] = 0x01;
		target[1] = 0x20;

		printf("Decruncher length = %d\n", decrLen);

		for(i = 0; i < decrLen; ++i)
		{
			target[i + 2] = decrCode[i];
		}

		printf("Crunched prg starts with:\n");
		for(int i=0; i<16; i++)
			printf("%02X ", obuf[i]);
		printf("\n");

		for(i = 0; i < put; ++i)
		{
			target[i + 2 + decrLen] = obuf[i];
		}

	}
	else
	{
		uint startAddress = (aSource->data[3] << 24) | (aSource->data[2] << 16) | (aSource->data[1] << 8) | aSource->data[0];

		printf("\n");
		printf("Original address:        0x%08X\n", startAddress);
		printf("Original size:           0x%08X\n", ibufSize);
		printf("Original end address:    0x%08X\n", startAddress+ibufSize);
		
		// -4 was -6 to end exactly at the end of the file, but it looks like I need 2 extra bytes overflow
		uint packedAddress = startAddress + (ibufSize - packLen - 4 + margin);

		printf("Original packed address: 0x%08X\n", packedAddress);

		if (isRelocated)
		{
			packedAddress = (address + ibufSize) - packLen - 8;
			printf("\nRelocated file to:       0x%08X\n", packedAddress);
		}

		printf("\n");
		printf("Packed Start address:    0x%08X\n", packedAddress);
		printf("Packed size:             0x%08X\n", packLen);
		printf("Packed end address:      0x%08X\n", packedAddress+packLen);
		printf("\n");

		target[0] = (packedAddress      ) & 0xff;				// Load address
		target[1] = (packedAddress >>  8) & 0xff;
		target[2] = (packedAddress >> 16) & 0xff;
		target[3] = (packedAddress >> 24) & 0xff;
		target[4] = aSource->data[0];							// Depack to address
		target[5] = aSource->data[1];
		target[6] = aSource->data[2];
		target[7] = aSource->data[3];

		for(i = 0; i < put; ++i)
		{
			target[i + 8] = obuf[i];
		}
	}

	free(ibuf);
	free(context);
	free(link);
	free(rleInfo);

	return true;
}
