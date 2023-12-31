#define PI 3.1415926535897932384626433832795

//I used mersenne twister's method to initialize variables
//Rng is 128 bit Xorshift implementation
uint RandomUInt(uint seed) {
	uint x = seed;
	uint y = 181243323 * (x ^ (x >> 30)) + 1;
	uint z = 181243323 * (y ^ (y >> 30)) + 2;
	uint w = 181243323 * (z ^ (z >> 30)) + 3;

	uint a = 11; //shift counts
	uint b = 19; //shift counts
	uint c = 8; //shift counts
	
	uint temp = x ^ (x << a);
	x = y;
	y = z;
	z = w;
	w = (w ^ (w >> b)) ^ (temp ^ (temp >> c));

	return w;
}


/* Constants and functions below are used to convert signed and unsigned integers to
		32 bit and 64 bit floating points, range[0,1)
		https://www.doornik.com/research/randomdouble.pdf
*/

#ifndef M_RAN_INVM32
#define M_RAN_INVM32 2.32830643653869628906e-010
#endif 

//uint to float converter
float UintToFloat(uint uiRan)
{
	return (float) ((int) uiRan * M_RAN_INVM32 + 0.5);
}

float interpolate(float a0, float a1, float w, int smoothness) {
	if (w < 0)
		w = 0;
	else if (w > 1.0f)
		w = 1.0f;

	switch (smoothness) {
		case 0:
			return (a1 - a0) * w + a0;
			break;
		case 1:
			return (a1 - a0) * (3.0f - w * 2.0f) * w * w + a0;
			break;
		case 2:
			return (a1 - a0) * ((w * (w * 6.0f - 15.0f) + 10.0f) * w * w * w) + a0;
			break;
		default:
			return (a1 - a0) * ((w * (w * 6.0f - 15.0f) + 10.0f) * w * w * w) + a0;
			break;
	}

	return 0;
}

float dotGridGradient(int ix, int iy, int iz, float x, float y, float z) {
	uint seed = (uint) ix;
	seed = seed << 12;
	seed += (uint) iy;
	seed = seed << 12;
	seed += (uint) iz;

	float r1 = UintToFloat(RandomUInt(seed));
	float r2 = UintToFloat(RandomUInt(seed + 7));

	float3 gradient;
	gradient.x = cos(PI * r1 * 2.0f) * sin(PI * r2);
	gradient.y = cos(PI * r2);
	gradient.z = sin(PI * r1 * 2.0f) * sin(PI * r2);

	float3 distance = float3(x - ix, y - iy, z - iz);

	return dot(gradient, distance);
}

float PerlinNoise(float x, float y, float z, int smoothness) {
	int x0 = (int) x;
	int x1 = (int) (x + 1);
	int y0 = (int) y;
	int y1 = (int) (y0 + 1);
	int z0 = (int) z;
	int z1 = (int) (z0 + 1);

	float sx = x - (float) x0;
	float sy = y - (float) y0;
	float sz = z - (float) z0;

	float n0, n1, n2, n3, ix0, ix1, iy0, iy1, value;

	n0 = dotGridGradient(x0, y0, z0, x, y, z);
	n1 = dotGridGradient(x1, y0, z0, x, y, z);
	ix0 = interpolate(n0, n1, sx, smoothness);

	n2 = dotGridGradient(x0, y1, z0, x, y, z);
	n3 = dotGridGradient(x1, y1, z0, x, y, z);
	ix1 = interpolate(n2, n3, sx, smoothness);

	iy0 = interpolate(ix0, ix1, sy, smoothness);

	n0 = dotGridGradient(x0, y0, z1, x, y, z);
	n1 = dotGridGradient(x1, y0, z1, x, y, z);
	ix0 = interpolate(n0, n1, sx, smoothness);

	n2 = dotGridGradient(x0, y1, z1, x, y, z);
	n3 = dotGridGradient(x1, y1, z1, x, y, z);
	ix1 = interpolate(n2, n3, sx, smoothness);

	iy1 = interpolate(ix0, ix1, sy, smoothness);

	value = interpolate(iy0, iy1, sz, smoothness);

	return value;
}

float3 randomPoint(int x0, int y0, int z0) {
	uint seed = (uint) x0;
	seed = seed << 12;
	seed += (uint) y0;
	seed = seed << 12;
	seed += (uint) z0;
	
	float x = UintToFloat(RandomUInt(seed));
	float y = UintToFloat(RandomUInt(seed + 7));
	float z = UintToFloat(RandomUInt(seed + 21));
	
	return float3(x, y, z);
}

float WorleyNoise(float x, float y, float z) {
	float3 origin = float3(x, y, z);
	
	int x0 = (int)x;
	int y0 = (int)y;
	int z0 = (int)z;
	
	float minDistance = 1;
	
	for (int z1 = -1; z1 <= 1; z1++) {
		for (int y1 = -1; y1 <= 1; y1++) {
			for (int x1 = -1; x1 <= 1; x1++) {
				float3 p = float3(x0 + x1, y0 + y1, z0 + z1) + randomPoint(x0 + x1, y0 + y1, z0 + z1);
				float distance = length(p - origin);
				if(minDistance > distance)
					minDistance = distance;
			}
		}
	}
	
	return 1.0f - interpolate(0, 1, minDistance, 1);
}