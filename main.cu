#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>
#include <vector>
#include <cmath>
#include <sys/time.h>
#include <chrono>
#include <cuda_profiler_api.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/scan.h>

using namespace std;

#define EXTEND_GAP -2
#define START_GAP -2
#define NBLOCKS 15000
#define MATCH 5
#define MISMATCH -3
#define NOW std::chrono::high_resolution_clock::now()

#define cudaErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char* file, int line, bool abort = true){

	if(code != cudaSuccess){
		fprintf(stderr, "GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
	if(abort) exit(code);
	}
}
//int ind;

//double similarityScore(char a, char b);
//double findMax(double array[], int length)

__inline__ __device__
short warpReduceMax(short val, short &myIndex, short &myIndex2) {
int warpSize = 32;
short myMax = 0;
short newInd = 0;
short newInd2 = 0;
short ind = myIndex;
short ind2 = myIndex2;


  myMax = val;
  unsigned mask = __ballot_sync(0xffffffff, threadIdx.x < blockDim.x);

  for (int offset = warpSize/2; offset > 0; offset /= 2){

    val = max(val,__shfl_down_sync(mask, val, offset));
    newInd = __shfl_down_sync(mask, ind, offset);
    newInd2 = __shfl_down_sync(mask, ind2, offset);

    if(val != myMax){

    	ind = newInd;
    	ind2 = newInd2;
    	myMax = val;

    	}
			__syncthreads();
    }
	__syncthreads();
		myIndex = ind;
		myIndex2 = ind2;
		val = myMax;
  return val;
}


__device__
short blockShuffleReduce(short myVal, short &myIndex, short &myIndex2){
	int laneId = threadIdx.x % 32;
	int warpId = threadIdx.x / 32;
	__shared__ short locTots[32];
	__shared__ short locInds[32];
	__shared__ short locInds2[32];
	short myInd = myIndex;
	short myInd2 = myIndex2;
	myVal = warpReduceMax(myVal, myInd, myInd2);


	if(laneId == 0) locTots[warpId] = myVal;
	if(laneId == 0) locInds[warpId] = myInd;
	if(laneId == 0) locInds2[warpId] = myInd2;

	__syncthreads();

	if(threadIdx.x <= (blockDim.x / 32)){
		myVal = locTots[threadIdx.x];
		myInd = locInds[threadIdx.x];
		myInd2 = locInds2[threadIdx.x];
	}else{
		myVal = 0;
		myInd = -1;
		myInd2 = -1;
	}
	__syncthreads();

	if(warpId == 0) {
	myVal = warpReduceMax(myVal, myInd, myInd2);
	myIndex = myInd;
	myIndex2 = myInd2;
}
return myVal;
}



__device__ __host__
double similarityScore(char a, char b)
{
	double result;
	if(a==b)
	{
		result=5;
	}
	else
	{
		result=-3;
	}
	return result;
}

__device__ __host__
 short findMax(short array[], int length, int *ind)
{
	short max = array[0];
	*ind = 0;

	for(int i=1; i<length; i++)
	{
		if(array[i] > max)
		{
			max = array[i];
			*ind=i;
		}
	}
	return max;
}

__device__
void traceBack(short current_i, short current_j, short* seqA_align_begin, short* seqB_align_begin,
const char* seqA, const char* seqB,short* I_i, short* I_j, unsigned lengthSeqB, unsigned lengthSeqA, unsigned int *diagOffset){
      // int current_i=i_max,current_j=j_max;
			//printf ("SeqA:%d SeqB:%d\n",lengthSeqA,lengthSeqB);
//if(blockIdx.x == 265)
		//	for(int i = lengthSeqA+lengthSeqB; i>lengthSeqA+lengthSeqB -10; i--){
		//		printf ("diagOffset:%d \n",diagOffset[i]);
		//	}
	int myId = blockIdx.x;
	unsigned short current_diagId;// = current_i+current_j;
	unsigned short current_locOffset;// = 0;

	current_diagId = current_i+current_j;
	current_locOffset = 0;
	if(current_diagId < lengthSeqA + 1){
		current_locOffset = current_j;
	}else{
		unsigned short myOff = current_diagId -lengthSeqA;
		current_locOffset = current_j - myOff;
	}
//	I_i[diagOffset[diagId]+locOffset] = i + iVal[ind]; // coalesced accesses,
//	I_j[diagOffset[diagId]+locOffset] = j + jVal[ind]; // coalesced accesses,
//printf ("current_i:%d current_j:%d\n",current_i,current_j);
//if(blockIdx.x==265)
//printf ("diagOffset:%d current_locOffset:%d\n",diagOffset[current_diagId],current_locOffset);


        short next_i=I_i[diagOffset[current_diagId]+current_locOffset];
        short next_j=I_j[diagOffset[current_diagId]+current_locOffset];
//printf ("next_i:%d next_j:%d\n",next_i,next_j);
//printf ("diagOffset:%d current_locOffset:%d\n",diagOffset[current_diagId],current_locOffset);

while(((current_i!=next_i) || (current_j!=next_j)) && (next_j!=0) && (next_i!=0))
        {


                current_i = next_i;
                current_j = next_j;

								current_diagId = current_i+current_j;
								current_locOffset = 0;
								if(current_diagId < lengthSeqA + 1){
									current_locOffset = current_j;
								}else{
									unsigned short myOff2 = current_diagId -lengthSeqA;
									current_locOffset = current_j - myOff2;
								}

                next_i = I_i[diagOffset[current_diagId]+current_locOffset];
                next_j = I_j[diagOffset[current_diagId]+current_locOffset];

        }
	//printf("final current_i=%d, current_j=%d\n", current_i, current_j);
	seqA_align_begin[myId] = current_i;
	seqB_align_begin[myId] = current_j;
	//printf("traceback done\n");

       // *tick_out = tick;
}


__global__
void align_sequences_gpu(char* seqA_array,char* seqB_array, unsigned* prefix_lengthA,
unsigned* prefix_lengthB, unsigned* prefix_matrices, short *I_i_array, short *I_j_array,
short* seqA_align_begin, short* seqA_align_end, short* seqB_align_begin, short* seqB_align_end){

	int myId = blockIdx.x;
	int myTId = threadIdx.x;

//	if(myId == 4)
//	printf("block3 lenA:%d",prefix_lengthA[myId]);
	unsigned lengthSeqA;
	unsigned lengthSeqB;
	unsigned matrixOffset;
	//local pointers
	char* seqA;
	char* seqB;
	short* I_i, *I_j;
	unsigned totBytes = 0;

	extern __shared__ char is_valid_array[];
	char* is_valid = &is_valid_array[0];

	if(myId == 0){
		lengthSeqA = prefix_lengthA[0];
		lengthSeqB = prefix_lengthB[0];
		matrixOffset = 0;
		seqA = seqA_array;
		seqB = seqB_array;
		I_i = I_i_array;
		I_j = I_j_array;
	}else{
		lengthSeqA = prefix_lengthA[myId] - prefix_lengthA[myId-1];
		lengthSeqB = prefix_lengthB[myId] - prefix_lengthB[myId-1];
		matrixOffset = prefix_matrices[myId-1];
		seqA = seqA_array + prefix_lengthA[myId-1];
		seqB = seqB_array + prefix_lengthB[myId-1];
		I_i = I_i_array + matrixOffset;
		I_j = I_j_array + matrixOffset;
	}

	short* curr_H = (short*)(&is_valid_array[3*lengthSeqB+(lengthSeqB&1)]);// point where the valid_array ends
	short* prev_H = &curr_H[lengthSeqB+1]; // where the curr_H array ends
	short* prev_prev_H = &prev_H[lengthSeqB+1];
	totBytes += (3*lengthSeqB+(lengthSeqB&1))*sizeof(char) + ((lengthSeqB+1) + (lengthSeqB+1))*sizeof(short);

	short* curr_E = &prev_prev_H[lengthSeqB+1];
	short* prev_E = &curr_E[lengthSeqB+1];
	short* prev_prev_E = &prev_E[lengthSeqB+1];
	totBytes += ((lengthSeqB+1) + (lengthSeqB+1) + (lengthSeqB+1))*sizeof(short);

	short* curr_F = &prev_prev_E[lengthSeqB+1];
	short* prev_F = &curr_F[lengthSeqB+1];
	short* prev_prev_F = &prev_F[lengthSeqB+1];
	totBytes += ((lengthSeqB+1) + (lengthSeqB+1) + (lengthSeqB+1))*sizeof(short);

  char* myLocString = (char*)&prev_prev_F[lengthSeqB+1];
	totBytes += (lengthSeqB+1)*sizeof(short) + (lengthSeqA)*sizeof(char);


//if(myTId == 0 && myId == 0)
	//printf("outalign: %d locAlign: %d", outalign, totBytes);
	unsigned alignmentPad = 4 - totBytes%4;
	unsigned int* diagOffset = (unsigned int*)&myLocString[lengthSeqA+alignmentPad];
	//char* v = is_valid;

__syncthreads();
//if(myTId == 0) {
	memset(is_valid, 0, lengthSeqB);
	is_valid += lengthSeqB;
	memset(is_valid, 1, lengthSeqB);
	is_valid += lengthSeqB;
	memset(is_valid, 0, lengthSeqB);





		memset(curr_H, 0, 9*(lengthSeqB+1)*sizeof(short));
	//}
	//__shared__ int global_max;
	__shared__ int i_max;
	__shared__ int j_max;
	int j = myTId+1;
 char myColumnChar = seqB[j-1]; // read only once

///////////locsl dtring read in
for(int i = myTId; i < lengthSeqA; i+=32){
		myLocString[i] = seqA[i];

}

	__syncthreads();



	short traceback[4];
	__shared__ short iVal[4]; //= {-1,-1,0,0};
	iVal[0] = -1; iVal[1] = -1; iVal[2] = 0; iVal[3] = 0;
	__shared__ short jVal[4]; //= {-1,0,-1,0};
	jVal[0] = -1; jVal[1] = 0; jVal[2] = -1; jVal[3] = 0;

	//__shared__ unsigned int diagOffset[1071+128+2]; //make this dynamic shared memory later on
	int ind;

	int i = 1;
	short thread_max = 0;
	short thread_max_i = 0;
	short thread_max_j = 0;

	short* tmp_ptr;
	int locSum = 0;
	for(int diag = 0; diag < lengthSeqA + lengthSeqB - 1; diag++){
	int locDiagId = diag + 1;
 if(myTId == 0){ // this computes the prefixSum for diagonal offset look up table.
	 if(locDiagId <= lengthSeqB + 1){
		 locSum += locDiagId;
		 diagOffset[locDiagId] = locSum;
	 }else if (locDiagId > lengthSeqA + 1){
		 locSum += (lengthSeqB + 1) - (locDiagId- (lengthSeqA+1));
		 diagOffset[locDiagId] = locSum;
	 }else{
		 locSum += lengthSeqB + 1;
		 diagOffset[locDiagId] = locSum;
	 }
		 diagOffset[lengthSeqA + lengthSeqB ] = locSum+2;
		//printf("diag:%d\tlocSum:%d\n",diag,diagOffset[locDiagId]);
 }
}
__syncthreads();
	for(int diag = 0; diag < lengthSeqA + lengthSeqB - 1; diag++){ // iterate for the number of anti-diagonals


		is_valid = is_valid - (diag < lengthSeqB || diag >= lengthSeqA);

		tmp_ptr = prev_H;
		prev_H = curr_H;
		curr_H = prev_prev_H;
		prev_prev_H = tmp_ptr;

		memset(curr_H, 0, (lengthSeqB+1)*sizeof(short));
		__syncthreads();
		tmp_ptr = prev_E;
		prev_E = curr_E;
		curr_E = prev_prev_E;
		prev_prev_E = tmp_ptr;

		memset(curr_E, 0, (lengthSeqB+1)*sizeof(short));
		__syncthreads();
		tmp_ptr = prev_F;
		prev_F = curr_F;
		curr_F = prev_prev_F;
		prev_prev_F = tmp_ptr;

		memset(curr_F, 0, (lengthSeqB+1)*sizeof(short));

		__syncthreads();

		if(is_valid[myTId]){
			short fVal = prev_F[j]+EXTEND_GAP;
			short hfVal = prev_H[j]+START_GAP;
			short eVal = prev_E[j-1]+EXTEND_GAP;
			short heVal = prev_H[j-1]+START_GAP;

			curr_F[j] = (fVal > hfVal) ? fVal : hfVal;
			curr_E[j] = (eVal > heVal) ? eVal: heVal;


 //(myLocString[i-1] == myColumnChar)?MATCH:MISMATCH

			traceback[0] = prev_prev_H[j-1]+((myLocString[i-1] == myColumnChar)?MATCH:MISMATCH);//similarityScore(myLocString[i-1],myColumnChar);//seqB[j-1]
			traceback[1] = curr_F[j];
			traceback[2] = curr_E[j];
			traceback[3] = 0;


			curr_H[j] = findMax(traceback,4,&ind);
		//	I_i[i*(lengthSeqB+1)+j] = i + iVal[ind]; // non-coalesced accesses, need to change
	//		I_j[i*(lengthSeqB+1)+j] = j + jVal[ind]; // non-coalesced accesses, need to change




/////////////////// coalesced version
///////////////
unsigned short diagId = i+j;
unsigned short locOffset = 0;
if(diagId < lengthSeqA + 1){
	locOffset = j;
}else{
	unsigned short myOff = diagId -lengthSeqA;
	locOffset = j - myOff;
}
I_i[diagOffset[diagId]+locOffset] = i + iVal[ind]; // coalesced accesses, need to change
I_j[diagOffset[diagId]+locOffset] = j + jVal[ind]; // coalesced accesses, need to change
/////////////
///////////

			thread_max_i = (thread_max >= curr_H[j]) ? thread_max_i : i;
			thread_max_j = (thread_max >= curr_H[j]) ? thread_max_j : myTId+1;
			thread_max = (thread_max >= curr_H[j]) ? thread_max : curr_H[j];


			i++;
        }
	}

	//atomicMax(&global_max, thread_max);
	thread_max = blockShuffleReduce(thread_max, thread_max_i, thread_max_j);// thread 0 will have the correct values
	//if(myId == 0 && myTId == 0)
			//printf("thread_max:%d thread_i:%d thread_j:%d \n",thread_max, thread_max_i, thread_max_j);

	// traceback
	if(myTId == 0) {
		i_max = thread_max_i;
		j_max = thread_max_j;
		short current_i=i_max,current_j=j_max;
		seqA_align_end[myId] = current_i;
		seqB_align_end[myId] = current_j;
//		for(int i = lengthSeqA+lengthSeqB; i>lengthSeqA+lengthSeqB -10; i--){
	//		printf ("diagOffset:%d \n",diagOffset[i]);
	//	}
		traceBack(current_i, current_j, seqA_align_begin, seqB_align_begin, seqA, seqB, I_i, I_j, lengthSeqB, lengthSeqA, diagOffset);

	}
	__syncthreads();
}

__host__
void traceBack_cpu(int current_i, int current_j, int* seqA_align_begin, int*seqB_align_begin, const char* seqA, const char* seqB,int lengthSeqA, int** I_i, int** I_j){
      // int current_i=i_max,current_j=j_max;
      //  int next_i=I_i[current_i][current_j];
       // int next_j=I_j[current_i][current_j];
        //int tick=0;
	cout << "lengthSeqA=" << lengthSeqA << endl;
        int next_i = I_i[current_i][current_j];
        int next_j = I_j[current_i][current_j];
	cout << "curr_i=" << current_i << ", curr_j=" << current_j << ", next_i=" << next_i << ", next_j=" << next_j << endl;
	printf("starting traceback\n");
        while(((current_i!=next_i) || (current_j!=next_j)) && (next_j!=0) && (next_i!=0))
        {


                current_i = next_i;
                current_j = next_j;
		cout << "curr_i=" << current_i << ", curr_j=" << current_j << endl;
                next_i = I_i[current_i][current_j];
                next_j = I_j[current_i][current_j];
                //*tick++;
        }
        *seqA_align_begin = current_i;
        *seqB_align_begin = current_j;
	//printf("traceback done\n");
  //return tick;
       // *tick_out = tick;
}

void align_sequences_cpu(const char* seqA, const char* seqB, int* seqA_align_begin, int* seqA_align_end, int* seqB_align_begin, int* seqB_align_end, int lengthA, int lengthB){


	// initialize some variables
	int lengthSeqA = lengthA;
	int lengthSeqB = lengthB;

	// initialize matrix
	double matrix[lengthSeqA+1][lengthSeqB+1];
	double Fmatrix[lengthSeqA+1][lengthSeqB+1];
	double Ematrix[lengthSeqA+1][lengthSeqB+1];

	for(int i=0;i<=lengthSeqA;i++)
	{
		for(int j=0;j<=lengthSeqB;j++)
		{
			matrix[i][j]=0;
			Fmatrix[i][j]=0;
			Ematrix[i][j]=0;
		}
	}

	short traceback[4];
	int **I_i;
	int **I_j;
	I_i = new int *[lengthSeqA+1];
	I_j = new int *[lengthSeqA+1];
	for(int i = 0; i < lengthSeqA+1; i++){
		I_i[i] = new int[lengthSeqB+1];
		I_j[i] = new int[lengthSeqB+1];
	}
	int ind;
	//start populating matrix
	for (int i=1;i<=lengthSeqA;i++)
	{
		for(int j=1;j<=lengthSeqB;j++)
        {                       // cout << i << " " << j << endl;

			Fmatrix[i][j] = ((Fmatrix[i-1][j]+EXTEND_GAP)>(matrix[i-1][j]+START_GAP)) ? Fmatrix[i-1][j]+EXTEND_GAP:matrix[i-1][j]+START_GAP;
			Ematrix[i][j] = ((Ematrix[i][j-1]+EXTEND_GAP)>(matrix[i][j-1]+START_GAP)) ? Ematrix[i][j-1]+EXTEND_GAP:matrix[i][j-1]+START_GAP;

			traceback[0] = matrix[i-1][j-1]+similarityScore(seqA[i-1],seqB[j-1]);
			traceback[1] = Fmatrix[i][j];
			traceback[2] = Ematrix[i][j];
			traceback[3] = 0;

			matrix[i][j] = findMax(traceback,4,&ind);
			switch(ind)
			{
				case 0:
					I_i[i][j] = i-1;
					I_j[i][j] = j-1;
					break;
				case 1:
					I_i[i][j] = i-1;
					I_j[i][j] = j;
                    			break;
				case 2:
					I_i[i][j] = i;
					I_j[i][j] = j-1;
                    			break;
				case 3:
					I_i[i][j] = i;
					I_j[i][j] = j;
                    			break;
			}
        }
	}


	// find the max score in the matrix
	cout << "lA =" << lengthSeqA << ", l B = " << lengthSeqB << endl;
	double matrix_max = 0;
	int i_max=0, j_max=0;
	for(int i=1;i<lengthSeqA;i++)
	{
		for(int j=1;j<lengthSeqB;j++)
		{
			if(matrix[i][j]>matrix_max)
			{
				matrix_max = matrix[i][j];
				i_max=i;
				j_max=j;
			}
		}
	}
	cout << "i_max =" << i_max << ", j_max=" << j_max << endl;

//	cout << "Max score in the matrix is " << matrix_max << endl;

	// traceback

	int current_i=i_max,current_j=j_max;
	int next_i=I_i[current_i][current_j];
	int next_j=I_j[current_i][current_j];
	//int tick=0;
	cout << "next_i_out=" << next_i << ", next_j_out=" << next_j << endl;
	*seqA_align_end = current_i;
	*seqB_align_end = current_j;
	traceBack_cpu(current_i, current_j, seqA_align_begin, seqB_align_begin, seqA, seqB, lengthSeqA, I_i, I_j);

}

int main()
{

	//READ SEQUENCE
	string seqB = /*"GGGAAAAAAAGGGG";*/"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGTTTTTTCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCAAAAAAAAAAAA";//AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGTTTTTTTTT"; // sequence A
	//CONTIG SEQUENCE
	string seqA = /*"AAAAAAA";*/"GAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGTTTTTTCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCAAAAAAAAAAAAAAAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGAAGAGAGAGAGGGG";//GAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAATTTTTTTTTTTTTTTTTTTTTTTTTT"; // sequence B
cout << "lengthA:"<<seqA.size()<<" lengthB:"<<seqB.size()<<endl;
  	vector<string> sequencesA, sequencesB;

	for(int i = 0; i < NBLOCKS; i++) {
  		sequencesA.push_back(seqA);
  		sequencesB.push_back(seqB);
	}
  	//
	unsigned nAseq = NBLOCKS;
	unsigned nBseq = NBLOCKS;

	thrust::host_vector<int> offsetA(sequencesA.size());
		thrust::host_vector<int> offsetB(sequencesB.size());
		thrust::device_vector<unsigned> vec_offsetA_d(sequencesA.size());
		thrust::device_vector<unsigned> vec_offsetB_d(sequencesB.size());

		thrust::host_vector<unsigned> offsetMatrix(NBLOCKS);//*sizeof(unsigned));
		thrust::device_vector<unsigned> vec_offsetMatrix_d(NBLOCKS);//*sizeof(unsigned));
			//offsetMatrix = (int*)malloc(NBLOCKS*sizeof(int));
			for(int i = 0; i < NBLOCKS; i++){
				offsetMatrix[i]=(sequencesA[i].size()+1)*(sequencesB[i].size()+1);
			}


	//	unsigned *offsetA = new unsigned[nAseq*sizeof(int)];
	//	unsigned *offsetB = new unsigned[nBseq*sizeof(int)];
	for(int i = 0; i < nAseq; i++){

		offsetA[i]=sequencesA[i].size();
	}

        for(int i = 0; i < nBseq; i++){

		offsetB[i]=sequencesB[i].size();
	}


  /*	offsetA[0]=sequencesA[0].size();
  	for(int i = 1; i < nAseq; i++){
  		offsetA[i]=offsetA[i-1]+sequencesA[i].size();
  	}

  	offsetB[0]=sequencesB[0].size();
  	for(int i = 1; i < nBseq; i++){
  		offsetB[i]=offsetB[i-1]+sequencesB[i].size();
  	}
*/
auto start = NOW;
 vec_offsetA_d = offsetA;
	vec_offsetB_d = offsetB;
cout <<"*******here here1"<<endl;
	thrust::inclusive_scan(vec_offsetA_d.begin(),vec_offsetA_d.end(),vec_offsetA_d.begin());
		thrust::inclusive_scan(vec_offsetB_d.begin(),vec_offsetB_d.end(),vec_offsetB_d.begin());

	unsigned totalLengthA =vec_offsetA_d[nAseq-1];
	unsigned totalLengthB =vec_offsetB_d[nBseq-1];

	cout << "lengthA:"<<totalLengthA<<endl;
	cout << "lengthB:"<<totalLengthB<<endl;
//  	unsigned totalLengthA = offsetA[nAseq-1];
  //	unsigned totalLengthB = offsetB[nBseq-1];
	unsigned* offsetA_d = thrust::raw_pointer_cast(&vec_offsetA_d[0]);
	unsigned* offsetB_d = thrust::raw_pointer_cast(&vec_offsetB_d[0]);
  	//declare A and B strings
	//char* strA, *strB;
  	//allocate and copy A string
  //	strA = (char*)malloc(sizeof(char)*totalLengthA);
  	//strB = (char*)malloc(sizeof(char)*totalLengthB);

//char *strA = new char[totalLengthA];
//char *strB = new char[totalLengthB];
unsigned offsetSumA = 0;
unsigned offsetSumB = 0;
cout <<"*******here here2"<<endl;

vec_offsetMatrix_d = offsetMatrix;

thrust::inclusive_scan(vec_offsetMatrix_d.begin(),vec_offsetMatrix_d.end(),vec_offsetMatrix_d.begin());

//char* strA, *strB;
	//allocate and copy A string
	//strA = (char*)malloc(sizeof(char)*totalLengthA);
//	strB = (char*)malloc(sizeof(char)*totalLengthB);
	char *strA = new char[totalLengthA];
		char *strB = new char[totalLengthB];
	for(int i = 0; i<nAseq; i++){
		char *seqptrA = strA + offsetSumA;//vec_offsetA_d[i] - sequencesA[i].size();
		memcpy(seqptrA, sequencesA[i].c_str(), sequencesA[i].size());

		char *seqptrB = strB + offsetSumB;// vec_offsetB_d[i] - sequencesB[i].size();
		memcpy(seqptrB, sequencesB[i].c_str(), sequencesB[i].size());
		offsetSumA += sequencesA[i].size();
		offsetSumB += sequencesB[i].size();
	}
/*
  	for(int i = 0; i<nAseq; i++){
  	 	char *seqptrA = strA + offsetSumA;//offsetA[i] - sequencesA[i].size();
  	 //	memcpy(seqptrA, sequencesA[i].c_str(), sequencesA[i].size());
			strcpy (seqptrA, sequencesA[i].c_str());
  	 	char *seqptrB = strB + offsetSumB;//offsetB[i] - sequencesB[i].size();
  	 	//memcpy(seqptrB, sequencesB[i].c_str(), sequencesB[i].size());
			strcpy (seqptrB, sequencesB[i].c_str());

			offsetSumA += sequencesA[i].size();
			offsetSumB += sequencesB[i].size();
		//	cout <<"offsetA:"<<offsetSumA<<endl;
		//	cout <<"offsetB:"<<offsetSumB<<endl;
	}*/
cout <<"*****here here3"<<endl;
  	//allocate and copy B string
  //	strB = (char*)malloc(sizeof(char)*totalLengthB);
  //	for(int i = 0; i<nBseq; i++){
  //	 	char *seqptr = strB + offsetB[i] - sequencesB[i].size();
  //	 	memcpy(seqptr, sequencesB[i].c_str(), sequencesB[i].size());
  //	}

//  	unsigned *offsetMatrix;
//  	offsetMatrix = (unsigned*)malloc(NBLOCKS*sizeof(int));
//  	offsetMatrix[0]=(sequencesA[0].size()+1)*(sequencesB[0].size()+1); // offsets for traceback matrices
//  	for(int i = 1; i < NBLOCKS; i++){
//  		offsetMatrix[i]=offsetMatrix[i-1]+(sequencesA[i].size()+1)*(sequencesB[i].size()+1);
//  	}


cout <<"*******here here7"<<endl;
//cout<<vec_offsetMatrix_d[0]<< " "<< vec_offsetMatrix_d[nAseq-1]<<endl;

	long dp_matrices_cells = vec_offsetMatrix_d[NBLOCKS-1];
unsigned* offsetMatrix_d = thrust::raw_pointer_cast(&vec_offsetMatrix_d[0]);

	//int lengthSeqB = seqB.size();

	char *strA_d, *strB_d;
	//unsigned *offsetA_d, *offsetB_d;
//	unsigned *offsetMatrix_d;
	short *I_i, *I_j; // device pointers for traceback matrices
	//double *matrix, *Ematrix, *Fmatrix;
  	short alAbeg[NBLOCKS], alBbeg[NBLOCKS], alAend[NBLOCKS], alBend[NBLOCKS];
  	short *alAbeg_d, *alBbeg_d, *alAend_d, *alBend_d;

	//cout << "allocating memory" << endl;

	cudaErrchk(cudaMalloc(&strA_d, totalLengthA*sizeof(char)));
	cudaErrchk(cudaMalloc(&strB_d, totalLengthB*sizeof(char)));

	//cout << "allocated strings"  << endl;
	//malloc matrices
//WHY ARW WE USING INTS FOR THIS??

//	long dp_matrices_cells = 0;
//	for(int i = 0; i < nAseq; i++) {
//		dp_matrices_cells += (sequencesA[i].size()+1) * (sequencesB[i].size()+1);
//	}
	cout << "dpcells:"<<endl<<dp_matrices_cells << endl;


	cudaErrchk(cudaMalloc(&I_i, dp_matrices_cells*sizeof(short)));
	cudaErrchk(cudaMalloc(&I_j, dp_matrices_cells*sizeof(short)));
	//cout << "allocating matrices" << endl;


// use character arrays for output data
	//allocating offsets
//	cudaErrchk(cudaMalloc(&offsetA_d, nAseq*sizeof(int))); // array for storing offsets for A
//	cudaErrchk(cudaMalloc(&offsetB_d, nBseq*sizeof(int)));  // array for storing offsets for B
//	cudaErrchk(cudaMalloc(&offsetMatrix_d, NBLOCKS*sizeof(int))); // array for storing ofsets for traceback matrix

	// copy back
  	cudaErrchk(cudaMalloc(&alAbeg_d, NBLOCKS*sizeof(short)));
  	cudaErrchk(cudaMalloc(&alBbeg_d, NBLOCKS*sizeof(short)));
  	cudaErrchk(cudaMalloc(&alAend_d, NBLOCKS*sizeof(short)));
  	cudaErrchk(cudaMalloc(&alBend_d, NBLOCKS*sizeof(short)));

//	for(int iter = 0; iter < 10; iter++){
cout <<"*******here here6"<<endl;
	cudaErrchk(cudaMemcpy(strA_d, strA, totalLengthA*sizeof(char), cudaMemcpyHostToDevice));
	cudaErrchk(cudaMemcpy(strB_d, strB, totalLengthB*sizeof(char), cudaMemcpyHostToDevice));
	//cudaErrchk(cudaMemcpy(offsetA_d, offsetA, nAseq*sizeof(int), cudaMemcpyHostToDevice));
//	cudaErrchk(cudaMemcpy(offsetB_d, offsetB, nBseq*sizeof(int), cudaMemcpyHostToDevice));
//	cudaErrchk(cudaMemcpy(offsetMatrix_d, offsetMatrix, NBLOCKS*sizeof(int), cudaMemcpyHostToDevice));

//cudaProfilerStart();
cout <<"*******here here4"<<endl;

unsigned totShmem = 3*3*(seqB.size()+1)*sizeof(short)+3*seqB.size()+(seqB.size()&1)+ seqA.size();
cout <<"shmem:"<<totShmem<<endl;
unsigned alignmentPad = 4 - totShmem%4;
  	cout << "alignmentpad:" <<alignmentPad<<endl;
	align_sequences_gpu<<<NBLOCKS, seqB.size(),totShmem+alignmentPad + sizeof(int)*(seqA.size()+seqB.size()+2)>>>(strA_d, strB_d, offsetA_d, offsetB_d, offsetMatrix_d, I_i, I_j, alAbeg_d, alAend_d, alBbeg_d, alBend_d);
cout <<"*******here here5"<<endl;
	//cout << "kernel launched" << endl;
//cudaProfilerStop();
//cudaDeviceSynchronize();
	cudaErrchk(cudaMemcpy(alAbeg, alAbeg_d, NBLOCKS*sizeof(short), cudaMemcpyDeviceToHost));
	cudaErrchk(cudaMemcpy(alBbeg, alBbeg_d, NBLOCKS*sizeof(short), cudaMemcpyDeviceToHost));
	cudaErrchk(cudaMemcpy(alAend, alAend_d, NBLOCKS*sizeof(short), cudaMemcpyDeviceToHost));
	cudaErrchk(cudaMemcpy(alBend, alBend_d, NBLOCKS*sizeof(short), cudaMemcpyDeviceToHost));

	//}
	auto end = NOW;
	chrono::duration<double> diff = end - start;
	cout << "time = " << diff.count() << endl;
	cudaErrchk(cudaFree(strA_d));
	cudaErrchk(cudaFree(strB_d));
	cudaErrchk(cudaFree(I_i));
	cudaErrchk(cudaFree(I_j));
//	cudaErrchk(cudaFree(offsetA_d));
//	cudaErrchk(cudaFree(offsetB_d));
//	cudaErrchk(cudaFree(offsetMatrix_d));

	cudaErrchk(cudaFree(alAbeg_d));
	cudaErrchk(cudaFree(alBbeg_d));
	cudaErrchk(cudaFree(alAend_d));
	cudaErrchk(cudaFree(alBend_d));

	cout << "startA=" << alAbeg[0] << ", endA=" << alAend[0] << " start2A=" << alAbeg[900] << " end2A=" << alAend[900] << endl;
	cout << "startB=" << alBbeg[0] << ", endB=" << alBend[0] << " start2B=" << alBbeg[900] << " end2B=" << alBend[900] << endl;



	return 0;
}
