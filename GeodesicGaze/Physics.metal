//
//  Physics.metal
//  GeodesicGaze
//
//  Created by Trevor Gravely on 9/2/24.
//

#include <metal_stdlib>
#include "Physics.h"
#include "MathFunctions.h"
#include "ComplexMath.h"

// TODO: switch to just using Result struct.

using namespace metal;

// The roots of the radial potential.
// ASSUMPTION: We assume that the caller
// ensures bc < b => bc / b < 1 such that
// we don't encounter domain issues with
// arctrig functions.
float4 radialRoots(float M, float b) {
    float bc = 3.0 * sqrt(3.0) * M;
    
    assert(bc < b);
    assert(bc < b);

    float r1 = (-2.0 * b / sqrt(3.0)) * cos((1.0 / 3.0) * acos(bc / b));
    float r2 = 0.0;
    float r3 = (2.0 * b / sqrt(3.0)) * sin((1.0 / 3.0) * asin(bc / b));
    float r4 = (2.0 * b / sqrt(3.0)) * cos((1.0 / 3.0) * acos(-1.0 * bc / b));
    
    return float4(r1, r2, r3, r4);
}

float3 computeABC(float a, float M, float eta, float lambda) {
    float A = a * a - eta - lambda * lambda;
    float B = 2.0 * M * (eta + (lambda - a) * (lambda - a));
    float C = -1.0 * a * a * eta;
    
    return float3(A,B,C);
}

float2 computePQ(float a, float M, float eta, float lambda) {
    float A = a * a - eta - lambda * lambda;
    float B = 2.0 * M * (eta + (lambda - a) * (lambda - a));
    float C = -1.0 * a * a * eta;
    
    float P = -1.0 * (A * A / 12.0) - C;
    float Q = -1.0 * (A / 3.0) * ((A / 6.0) * (A / 6.0) - C) - B * B / 8.0;

    return float2(P, Q);
}

KerrRadialRootsResult kerrRadialRoots(float a, float M, float eta, float lambda) {
    KerrRadialRootsResult result;
    
    float A = a * a - eta - lambda * lambda;
    float B = 2.0 * M * (eta + (lambda - a) * (lambda - a));
    float C = -1.0 * a * a * eta;
    
    float P = -1.0 * (A * A / 12.0) - C;
    float Q = -1.0 * (A / 3.0) * ((A / 6.0) * (A / 6.0) - C) - B * B / 8.0;
    
    float2 term;
    float termUnderRadical = pow(P / 3.0, 3.0) + pow(Q / 2.0, 2.0);
    if (termUnderRadical < 0.0) {
        term = float2(0, 1) * sqrt(-1 * termUnderRadical);
    } else {
        term = float2(1, 0) * sqrt(termUnderRadical);
    }
    
    float2 otherTerm = (-1.0 * Q / 2.0) * float2(1.0, 0.0);
    float2 omegaplus = pow1over3(otherTerm + term);
    float2 omegaminus = pow1over3(otherTerm - term);
    
    float2 xi0 = omegaplus + omegaminus - (A / 3.0) * float2(1.0, 0.0);
    
    
    bool imaginaryPartVanishes = fEqual(FLT_EPSILON, xi0.y);
    assert(imaginaryPartVanishes);
    
    float z = sqrt(xi0.x / 2.0);
    
    float2 r1, r2;
    termUnderRadical = (-1.0 * A / 2.0) - z * z + (B / (4.0 * z));
    if (termUnderRadical < 0.0) {
        r1 = -1.0 * z * float2(1.0, 0.0) - float2(0.0, 1.0) * sqrt(-1.0 * termUnderRadical);
        r2 = -1.0 * z * float2(1.0, 0.0) + float2(0.0, 1.0) * sqrt(-1.0 * termUnderRadical);
    } else {
        r1 = -1.0 * z * float2(1.0, 0.0) - float2(1.0, 0.0) * sqrt(termUnderRadical);
        r2 = -1.0 * z * float2(1.0, 0.0) + float2(1.0, 0.0) * sqrt(termUnderRadical);
    }
    
    float2 r3, r4;
    termUnderRadical = (-1.0 * A / 2.0) - z * z - (B / (4.0 * z));
    if (termUnderRadical < 0.0) {
        r3 = z * float2(1.0, 0.0) - float2(0.0, 1.0) * sqrt(-1.0 * termUnderRadical);
        r4 = z * float2(1.0, 0.0) + float2(0.0, 1.0) * sqrt(-1.0 * termUnderRadical);
    } else {
        r3 = z * float2(1.0, 0.0) - float2(1.0, 0.0) * sqrt(termUnderRadical);
        r4 = z * float2(1.0, 0.0) + float2(1.0, 0.0) * sqrt(termUnderRadical);
    }

    result.status = SUCCESS;
    result.roots[0] = r1;
    result.roots[1] = r2;
    result.roots[2] = r3;
    result.roots[3] = r4;
    
    return result;
}

EllintResult mathcalF(float M, float r, float b, float modulus) {
    assert(0 <= modulus);
    
    float4 roots = radialRoots(M, b);
    float r1 = roots[0];
    float r2 = roots[1];
    float r3 = roots[2];
    float r4 = roots[3];
    
    float arg = asin(sqrt(((r - r4) / (r - r3)) * ((r3 - r1) / (r4 - r1))));
    
    return ellint_F(arg, sqrt(modulus), 1e-5, 1e-5);
}

PhiSResult phiS(float M, float ro, float rs, float b) {
    PhiSResult result;
    
    // Note that phiS is only called when bc < b, such that
    // radialRoots requirements are met.
    float4 roots = radialRoots(M, b);
    
    float r1 = roots[0];
    float r2 = roots[1];
    float r3 = roots[2];
    float r4 = roots[3];

    float modulus = ((r3 - r2) * (r4 - r1)) / ((r3 - r1) * (r4 - r2));
    float prefactor = (2 * b) / (sqrt((r3 - r1) * (r4 - r2)));
    
    EllintResult roF = mathcalF(M, ro, b, modulus);
    EllintResult rsF = mathcalF(M, rs, b, modulus);
    
    if (roF.status != SUCCESS || rsF.status != SUCCESS) {
        result.val = 0.0;
        result.status = FAILURE;
        return result;
    }
    
    result.val = prefactor * (roF.val + rsF.val);
    result.status = SUCCESS;
    return result;
}

SchwarzschildLenseResult schwarzschildLense(float M, float ro, float rs, float b) {
    SchwarzschildLenseResult result;
    
    // If we have b < bc, then the photon trajectory enters the horizon.
    float bc = 3.0 * sqrt(3.0) * M;
    if (b < bc) {
        result.status = EMITTED_FROM_BLACK_HOLE;
        return result;
    }
    
    /*
    * The value of lambda is the initial angular momenta of the light ray.
    * We use this initial condition to ray trace the light ray into the
    * Schwarzschild geometry. In particular, we compute the accrued azimuthal
    * rotation of the resulting ray as it traverses out to rs.
     */
    
    PhiSResult phiSResult = phiS(M, ro, rs, b);
    if (phiSResult.status == FAILURE) {
        result.status = FAILURE;
        return result;
    }
    float phiS = phiSResult.val;
    
    /*
    * We now consider the triangle formed via A = (r = rs, \phi = \Delta \phi),
    * B = the origin, and C = (r = ro, \phi = 0). This defines an angle BCA,
    * which is the incidence angle of the corresponding flat space light ray
    * that interects the source point at rs. The angle ABC is easily computed
    * from the value of \Delta \phi. The triangle can then be solved for the angle
    * of interest, BCA.
    */
    
    // Normalize the angle to lie between 0 and 2 pi
    float normalizedAngle = normalizeAngle(phiS);
    result.phif = normalizedAngle;
    
    // Obtain the angle ABC, along with the direction of the angle
    // away from the line of sight.
    float ABC = 0.0;
    bool ccw = false;
    
    if (fEqual(normalizedAngle, M_PI_F)) {
        result.varphitilde = 0;
        result.ccw = true;
        result.status = SUCCESS;
        return result;
    } else if (fEqual(normalizedAngle, 0) || fEqual(normalizedAngle, 2.0 * M_PI_F)) {
        result.varphitilde = M_PI_F;
        result.ccw = true;
        result.status = SUCCESS;
        return result;
    } else if (0 < normalizedAngle < M_PI_F) {
        // If the source location is in the upper half plane, then
        // the obtained angle of the triangle is a rotation cw.
        ABC = normalizedAngle;
        ccw = false;
    } else if (M_PI_F < normalizedAngle < 2.0 * M_PI_F) {
        // If the source location is in the lower half plane, then
        // the obtained angle of the triangle is a rotation ccw.
        ABC = 2 * M_PI_F - normalizedAngle;
        ccw = true;
    } else {
        assert(false);
    }
    result.ccw = ccw;

    // Use the law of cosines to obtain the missing side length
    float AC = sqrt(ro * ro + rs * rs - 2 * ro * rs * cos(ABC));
    
    // Two possibilities when using asin
    float BCA1 = asin((sin(ABC) / AC) * rs);
    float BCA2 = M_PI_F - BCA1;
    
    // To determine which is the angle of the triangle, check
    // the law of sines for all sides. You will run into
    // precision issues when checking for equality, so pick the
    // one that is closest.
    float diff1 = fabs((AC / sin(ABC)) - (ro / sin(M_PI_F - (BCA1 + ABC))));
    float diff2 = fabs((AC / sin(ABC)) - (ro / sin(M_PI_F - (BCA2 + ABC))));
    
    result.varphitilde = diff1 < diff2 ? BCA1 : BCA2;
    result.status = SUCCESS;
    return result;
}

F2ofrResult F2ofr(float r, float r1, float r2, float r3, float r4) {
    F2ofrResult result;
    
    float x2 = sqrt(((r - r4) / (r - r3)) * ((r3 - r1) / (r4 - r1)));
    float prefactor = 2.0 / sqrt((r3 - r1) * (r4 - r2));
    float phi = asin(x2);
    float k = ((r3 - r2) * (r4 - r1)) / ((r3 - r1) * (r4 - r2));
    
    EllintResult ellintResult = ellint_F_mma(phi, k, 1e-5, 1e-5);
    
    result.status = ellintResult.status;
    result.val = prefactor * ellintResult.val;
    return result;
}

// NOTE: We differ from 1910.12881 in notations ro <--> rs, since we think
// of the camera as the "observer." However, in that reference the "observer"
// is the endpoint of the result of evolving the geodesic, which in the framing
// here is the "source."
IrResult computeIr(float a, float M, float ro, float rs, float r1, float r2, float r3, float r4) {
    IrResult result;
    
    F2ofrResult F2ofroResult = F2ofr(ro, r1, r2, r3, r4);
    F2ofrResult F2ofrsResult = F2ofr(rs, r1, r2, r3, r4);
    if (F2ofroResult.status != SUCCESS || F2ofrsResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    
    float F2ofro = F2ofroResult.val;
    float F2ofrs = F2ofrsResult.val;
    
    result.val = F2ofro + F2ofrs;
    result.status = SUCCESS;
    return result;
}

MathcalGResult mathcalGtheta(float a, float theta, float uplus, float uminus) {
    MathcalGResult result;
    
    float prefactor = -1.0 / sqrt(-1.0 * uminus * a * a);
    float phi = asin(cos(theta) / sqrt(uplus));
    float k = uplus / uminus;
    
    EllintResult ellintResult = ellint_F_mma(phi, k, 1e-5, 1e-5);
    if (ellintResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float ellint_F = ellintResult.val;
    
    result.val = prefactor * ellint_F;
    result.status = SUCCESS;
    return result;
}

Result mathcalGphi(float a, float theta, float uplus, float uminus) {
    Result result;
    
    float prefactor = -1.0 / sqrt(-1.0 * uminus * a * a);
    
    float n = uplus;
    
    float phi = asin(cos(theta) / sqrt(uplus));
    float k = uplus / uminus;
    
    EllintResult ellintResult = ellint_P_mma(phi, k, n, 1e-5, 1e-5);
    if (ellintResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float ellint_P = ellintResult.val;
    
    result.val = prefactor * ellint_P;
    result.status = SUCCESS;
    return result;
}

// We assume non-vortical values of eta and lambda have been passed.
CosThetaObserverResult cosThetaObserver(float nuthetas, float tau, float a, float M, float thetas, float eta, float lambda) {
    CosThetaObserverResult result;
    
    float deltaTheta = (1.0 / 2.0) * (1.0 - (eta + lambda * lambda) / (a * a));
    
    
    /*
    float uplus = deltaTheta + sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
    float uminus = deltaTheta - sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
    */
    float2 uplusUminus = computeUplusUminus(a, eta, lambda);
    
    float uplus = uplusUminus.x;
    float uminus = uplusUminus.y;
     
    MathcalGResult mathcalGthetaResult = mathcalGtheta(a, thetas, uplus, uminus);
    if (mathcalGthetaResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float mathcalGthetas = mathcalGthetaResult.val;
    
    float u = sqrt(-1.0 * uminus * a * a) * (tau + nuthetas * mathcalGthetas);
    float m = uplus / uminus;

    ElljacResult ellipjResult = ellipj(u, m);
    if (ellipjResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    
    result.val = -1.0 * nuthetas * sqrt(uplus) * ellipjResult.sn;
    result.status = SUCCESS;
    return result;
}

Result Psitau(float a, float uplus, float uminus, float tau, float thetas, float nuthetas) {
    Result result;
    
    MathcalGResult mathcalGthetasResult = mathcalGtheta(a, thetas, uplus, uminus);
    if (mathcalGthetasResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float mathcalGthetas = mathcalGthetasResult.val;
    
    float u = sqrt(-1.0 * uminus * a * a) * (tau + nuthetas * mathcalGthetas);
    float m = uplus / uminus;
    
    EllamResult amResult = jacobiam(u, m);
    if (amResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    
    result.val = amResult.am;
    result.status = SUCCESS;
    return result;
}

float2 computeUplusUminus(float a, float eta, float lambda) {
    float deltaTheta = (1.0 / 2.0) * (1.0 - (eta + lambda * lambda) / (a * a));
    
    float alpha = eta / (a * a);
    float epsilon = alpha / (deltaTheta * deltaTheta);
    
    float uplus, uminus;
    if (epsilon < 0.001) {
        float linearOrder = (sqrt(deltaTheta * deltaTheta) / 2.0) * epsilon;
        
        if (deltaTheta < 0.0) {
            uplus = linearOrder;
            uminus = deltaTheta - sqrt(deltaTheta * deltaTheta) - linearOrder;
        } else {
            uplus = deltaTheta + sqrt(deltaTheta * deltaTheta) + linearOrder;
            uminus = -1.0 * linearOrder;
        }
    } else {
        uplus = deltaTheta + sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
        uminus = deltaTheta - sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
    }
    
    /*
    if (1.0 <= uplus) {
        uplus = 0.999;
    }
    */
    
    return float2(uplus, uminus);
}

Result computeGphi(float nuthetas, float tau, float a, float M, float thetas, float eta, float lambda) {
    Result result;
    
    float2 uplusUminus = computeUplusUminus(a, eta, lambda);
    
    float uplus = uplusUminus.x;
    float uminus = uplusUminus.y;
    
    Result mathcalGphiResult = mathcalGphi(a, thetas, uplus, uminus);
    if (mathcalGphiResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float mathcalGphis = mathcalGphiResult.val;
    
    Result psiTauResult = Psitau(a, uplus, uminus, tau, thetas, nuthetas);
    if (psiTauResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float psiTau = psiTauResult.val;
    
    EllintResult ellipticPResult = ellint_P_mma(psiTau, uplus / uminus, uplus, 1e-5, 1e-5);
    if (ellipticPResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }

    result.val = (1.0 / sqrt(-1.0 * uminus * a * a)) * ellipticPResult.val - nuthetas * mathcalGphis;
    result.status = SUCCESS;
    return result;
}

Result computePi2ofr(float r, float rplus, float rminus, float r1, float r2, float r3, float r4, float ro, float rs, bool isPlus) {
    Result result;
    
    float prefactor1 = 2.0 / sqrt((r3 - r1) * (r4 - r2));
    float prefactor2;
    if (isPlus) {
        prefactor2 = (r4 - r3) / ((rplus - r3) * (rplus - r4));
    } else {
        prefactor2 = (r4 - r3) / ((rminus - r3) * (rminus - r4));
    }
    
    float n;
    if (isPlus) {
        n = ((rplus - r3) * (r4 - r1)) / ((rplus - r4) * (r3 - r1));
    } else {
        n = ((rminus - r3) * (r4 - r1)) / ((rminus - r4) * (r3 - r1));
    }
    float x2 = sqrt(((r - r4) / (r - r3)) * ((r3 - r1) / (r4 - r1)));
    float k = ((r3 - r2) * (r4 - r1)) / ((r3 - r1) * (r4 - r2));
    
    EllintResult ellipticPResult = ellint_P_mma(asin(x2), k, n, 1e-5, 1e-5);
    if (ellipticPResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    
    result.val = prefactor1 * prefactor2 * ellipticPResult.val;
    result.status = SUCCESS;
    return result;
}

Result computeIminus(float rplus, float rminus, float r1, float r2, float r3, float r4, float ro, float rs) {
    Result result;
    
    Result Pi2ofroResult = computePi2ofr(ro, rplus, rminus, r1, r2, r3, r4, ro, rs, false);
    Result Pi2ofrsResult = computePi2ofr(rs, rplus, rminus, r1, r2, r3, r4, ro, rs, false);
    if (Pi2ofroResult.status != SUCCESS || Pi2ofrsResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float Pi2ofro = Pi2ofroResult.val;
    float Pi2ofrs = Pi2ofrsResult.val;
    
    F2ofrResult F2ofroResult = F2ofr(ro, r1, r2, r3, r4);
    F2ofrResult F2ofrsResult = F2ofr(rs, r1, r2, r3, r4);
    if (F2ofroResult.status != SUCCESS || F2ofrsResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float F2ofro = F2ofroResult.val;
    float F2ofrs = F2ofrsResult.val;

    float mathcalIplusatro = -1.0 * Pi2ofro - F2ofro / (rminus - r3);
    float mathcalIplusatrs = -1.0 * Pi2ofrs - F2ofrs / (rminus - r3);
    
    // TODO: is this sign correct???
    result.val = (mathcalIplusatro + mathcalIplusatrs);
    result.status = SUCCESS;
    return result;
}

Result computeIplus(float rplus, float rminus, float r1, float r2, float r3, float r4, float ro, float rs) {
    Result result;
    
    Result Pi2ofroResult = computePi2ofr(ro, rplus, rminus, r1, r2, r3, r4, ro, rs, true);
    Result Pi2ofrsResult = computePi2ofr(rs, rplus, rminus, r1, r2, r3, r4, ro, rs, true);
    if (Pi2ofroResult.status != SUCCESS || Pi2ofrsResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float Pi2ofro = Pi2ofroResult.val;
    float Pi2ofrs = Pi2ofrsResult.val;
    
    F2ofrResult F2ofroResult = F2ofr(ro, r1, r2, r3, r4);
    F2ofrResult F2ofrsResult = F2ofr(rs, r1, r2, r3, r4);
    if (F2ofroResult.status != SUCCESS || F2ofrsResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float F2ofro = F2ofroResult.val;
    float F2ofrs = F2ofrsResult.val;

    float mathcalIplusatro = -1.0 * Pi2ofro - F2ofro / (rplus - r3);
    float mathcalIplusatrs = -1.0 * Pi2ofrs - F2ofrs / (rplus - r3);
    
    // TODO: is this sign correct???
    result.val = (mathcalIplusatro + mathcalIplusatrs);
    result.status = SUCCESS;
    return result;
}

Result computeIphi(float a, float M, float eta, float lambda, float ro, float rs, float r1, float r2, float r3, float r4) {
    Result result;
    
    float rplus     = M + sqrt(M * M - a * a);
    float rminus    = M - sqrt(M * M - a * a);
    
    float prefactor = (2.0 * M * a) / (rplus - rminus);
    
    Result IplusResult = computeIplus(rplus, rminus, r1, r2, r3, r4, ro, rs);
    if (IplusResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float Iplus = IplusResult.val;
    
    Result IminusResult = computeIminus(rplus, rminus, r1, r2, r3, r4, ro, rs);
    if (IminusResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float Iminus = IminusResult.val;
    
    result.val = prefactor * ((rplus - (a * lambda) / (2.0 * M)) * Iplus - (rminus - (a * lambda) / (2.0 * M)) * Iminus);
    result.status = SUCCESS;
    return result;
}

/*
* NOTE - the interface for this function is different from
* schwarzschildLense(). Here, we pass values of eta, lambda
* and obtain the resulting values of (r_s, theta_s, phi_s).
* One still needs to obtain the corresponding eta, lambda
* for the flat space geodesic.
*/
KerrLenseResult kerrLense(float a, float M, float thetas, float nuthetas, float ro, float rs, float eta, float lambda) {
    KerrLenseResult result;
    
    KerrRadialRootsResult rootsResult = kerrRadialRoots(a, M, eta, lambda);
    if (rootsResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float2 roots[4];
    roots[0] = rootsResult.roots[0];
    roots[1] = rootsResult.roots[1];
    roots[2] = rootsResult.roots[2];
    roots[3] = rootsResult.roots[3];
    
    // If not in case (2), then black hole emission.
    if (!(isReal(roots[0]) &&
          isReal(roots[1]) &&
          isReal(roots[2]) &&
          isReal(roots[3]))) {
        result.status = EMITTED_FROM_BLACK_HOLE;
        return result;
    }
    
    float r1 = roots[0].x;
    float r2 = roots[1].x;
    float r3 = roots[2].x;
    float r4 = roots[3].x;

    // Ensure we are in the subcase of (2) in which
    // a turning point sits outside the horizon.
    float rplus = M + sqrt(M * M - a * a);
    if (r4 < rplus) {
        result.status = EMITTED_FROM_BLACK_HOLE;
        return result;
    }
    
    /*
     * Obtain the value of Ir. This gives us the elapsed mino time on the
     * trajectory. Alex and Sam provide inversions for the coordinate
     * trajectories as a function of mino time.
    */
    IrResult IrResult = computeIr(a, M, ro, rs, r1, r2, r3, r4);
    if (IrResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float Ir = IrResult.val;
    float tau = Ir;
    
    /*
     * With the mino time in hand, we can compute the value of theta_o, the
     * polar angle of the point of intersection between the trajectory and
     * the "source sphere."
     */
    CosThetaObserverResult cosThetaObserverResult = cosThetaObserver(nuthetas, tau, a, M, thetas, eta, lambda);
    if (cosThetaObserverResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float cosThetaObserver = cosThetaObserverResult.val;
    
    Result GphiResult = computeGphi(nuthetas, tau, a, M, thetas, eta, lambda);
    if (GphiResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float Gphi = GphiResult.val;
    
    Result IphiResult = computeIphi(a, M, eta, lambda, ro, rs, r1, r2, r3, r4);
    if (IphiResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float Iphi = IphiResult.val;
    
    result.costhetaf = cosThetaObserver;
    result.phif = Iphi + lambda * Gphi;
    result.status = SUCCESS;
    return result;
}

/*
 * Given initial and final positions (computed via the lensing calculation)
 * obtain the values of eta and lambda in flat space that yield a trajectory
 * that intersects these positions.
 */
FlatSpaceEtaLambdaResult flatSpaceEtaLambda(float rs, float thetas, float phis, float ro, float thetao, float phio) {
    FlatSpaceEtaLambdaResult result;
    
    float xs = rs * sin(thetas) * cos(phis);
    float ys = rs * sin(thetas) * sin(phis);
    float zs = rs * cos(thetas);
    
    float xo = ro * sin(thetao) * cos(phio);
    float yo = ro * sin(thetao) * sin(phio);
    float zo = ro * cos(thetao);

    float deltaX = xo - xs;
    float deltaY = yo - ys;
    float deltaZ = zo - zs;
    
    float denom = sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ);
    
    float ux = deltaX / denom;
    float uy = deltaY / denom;
    float uz = deltaZ / denom;
    
    // Jacobian elements
    float dthetadx = (xs * zs) / (rs * rs * sqrt(xs * xs + ys * ys));
    float dthetady = (ys * zs) / (rs * rs * sqrt(xs * xs + ys * ys));
    float dthetadz = (-1.0 * (xs * xs + ys * ys)) / (rs * rs * sqrt(xs * xs + ys * ys));
    
    float dphidx = (-1.0 * ys) / (xs * xs + ys * ys);
    float dphidy = xs / (xs * xs + ys * ys);
    float dphidz = 0;
    
    // Velocity in spherical coordinates
    float uphi = dphidx * ux + dphidy * uy + dphidz * uz;
    float utheta = dthetadx * ux + dthetady * uy + dthetadz * uz;
    result.uthetaSign = sign(utheta);
    
    // Lower the indices using the Minkowski metric's spherical components
    float uphilower = rs * rs * sin(thetas) * sin(thetas) * uphi;
    float uthetalower = rs * rs * utheta;
    
    result.lambdaflat = uphilower;
    result.etaflat = uthetalower * uthetalower + tan(thetas - (M_PI_F / 2.0)) * tan(thetas - (M_PI_F / 2.0)) * uphilower * uphilower;
    result.status = SUCCESS;
    return result;
}
