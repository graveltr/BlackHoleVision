//
//  Physics.h
//  GeodesicGaze
//
//  Created by Trevor Gravely on 9/2/24.
//

#ifndef Physics_h
#define Physics_h

#define EMITTED_FROM_BLACK_HOLE 3
#define IMAGINARY_VALUE_ENCOUNTERED 4

struct IrResult {
    float val;
    int status;
};

struct SchwarzschildLenseResult {
    float varphitilde;
    float phif;
    bool ccw;
    int status;
};

struct KerrLenseResult {
    float costhetaf;
    float phif;
    int status;
};

struct FlatSpaceEtaLambdaResult {
    float etaflat;
    float lambdaflat;
    float uthetaSign;
    int status;
};

struct PhiSResult {
    float val;
    int status;
};

struct KerrRadialRootsResult {
    float2 roots[4];
    int status;
};

struct CosThetaObserverResult {
    float val;
    int status;
};

struct Result {
    float val;
    int status;
};

struct F2ofrResult {
    float val;
    int status;
};

struct IphiResult {
    float val;
    int status;
};

struct MathcalGResult {
    float val;
    int status;
};


float4 radialRoots(float M, float b);
float3 computeABC(float a, float M, float eta, float lambda);
float2 computePQ(float a, float M, float eta, float lambda);
float2 computeUplusUminus(float a, float eta, float lambda);
IrResult computeIr(float a, float M, float ro, float rs, float r1, float r2, float r3, float r4);
Result computeGphi(float nuthetas, float tau, float a, float M, float thetas, float eta, float lambda);
Result mathcalGphi(float a, float theta, float uplus, float uminus);
MathcalGResult mathcalGtheta(float a, float theta, float uplus, float uminus);
Result Psitau(float a, float uplus, float uminus, float tau, float thetas, float nuthetas);
KerrRadialRootsResult kerrRadialRoots(float a, float M, float eta, float lambda);
KerrLenseResult kerrLense(float a, float M, float thetas, float nuthetas, float ro, float rs, float eta, float lambda);
FlatSpaceEtaLambdaResult flatSpaceEtaLambda(float rs, float thetas, float phis, float ro, float thetao, float phio);
CosThetaObserverResult cosThetaObserver(float nuthetas, float tau, float a, float M, float thetas, float eta, float lambda);
Result computeIphi(float a, float M, float eta, float lambda, float ro, float rs, float r1, float r2, float r3, float r4);

PhiSResult phiS(float M, float ro, float rs, float b);

/*
* Given a conserved value of b (angular momentum), an observer radius, and a source radius,
* determine the point at which a null geodesic in Schwarzschild would intersect
* the source radius, if fired from the observer.
*
* Then compute the angle of incidence that a light ray would have in flat space,
* such that it intersects this point, and return that value.
*
* The returned angle of incidence is about the line of sight. The boolean value
* ccw indicates whether it is clockwise or counter-clockwise.
*/
SchwarzschildLenseResult schwarzschildLense(float M, float ro, float rs, float b);

#endif /* Physics_h */
