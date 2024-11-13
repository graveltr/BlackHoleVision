//
//  MathFunctions.metal
//  MetalLibraryTester
//
//  Created by Trevor Gravely on 8/15/24.
//

#include <metal_stdlib>
#include "MathFunctions.h"

using namespace metal;

// Return the sign of x.
inline int gsl_sign(float x) {
    return (x > 0) ? 1 : ((x < 0) ? -1 : 0);
}

inline int ERROR_SELECT_2(int status1, int status2) {
    return (status1 != SUCCESS) ? status1 : ((status2 != SUCCESS) ? status2 : SUCCESS);
}

inline int ERROR_SELECT_3(int status1, int status2, int status3) {
    return (status1 != SUCCESS) ? status1 : ERROR_SELECT_2(status2, status3);
}

// Compute the length of the hypotenuse of a triangle
// with legs x and y.
inline float gsl_hypot(float x, float y) {
    return sqrt(x * x + y * y);
}

float add(float a, float b) {
    return a + b;
}

float multiply(float a, float b) {
    return a * b;
}

float2 complex_add(float2 z, float2 w) {
    return float2(z.x + w.x, z.y + w.y);
}

float2 complex_sub(float2 z, float2 w) {
    return float2(z.x - w.x, z.y - w.y);
}

float2 complex_mul(float2 z, float2 w) {
    return float2(z.x * w.x - z.y * w.y, z.y * w.x + z.x * w.y);
}

float2 complex_conj(float2 z) {
    return float2(z.x, -z.y);
}

// Return the polar coordinates of z in 2d float vector.
// The first entry is the magnitude, the second is the polar angle.
float2 cartesian_to_polar(float2 z) {
    return float2(sqrt(z.x * z.x + z.y * z.y), atan(z.y/z.x));
}

// Convert from polar form back to cartesian.
float2 polar_to_cartesian(float mag, float angle) {
    return float2(mag * cos(angle), mag * sin(angle));
}

// Compute z^alpha.
float2 complex_pow(float2 z, float alpha) {
    float2 polarCoords = cartesian_to_polar(z);
    return polar_to_cartesian(pow(polarCoords.x, alpha), alpha * polarCoords.y);
}

ASinOfSnShiftedResult asinOfSnShifted(float u, float m, float xShift, float yShift) {
    ASinOfSnShiftedResult result;
    
    ElljacResult ellipjResult = ellipj(u - xShift, m);
    if (ellipjResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float sn = ellipjResult.sn;
    
    result.val = asin(sn) + yShift;
    result.status = SUCCESS;
    return result;
}

EllamResult jacobiamShifted(float u, float m, float ellipticKofm, float yShift) {
    EllamResult result;
    
    float deltaX = 2 * ellipticKofm;
    ASinOfSnShiftedResult asinOfSnShiftedOfDeltaXResult = asinOfSnShifted(deltaX, m, ellipticKofm, yShift);
    if (asinOfSnShiftedOfDeltaXResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    
    float deltaY = asinOfSnShiftedOfDeltaXResult.val;
    int n = floor(u / deltaX);
    float r = u - n * deltaX;
    
    ASinOfSnShiftedResult asinOfSnShiftedOfrResult = asinOfSnShifted(r, m, ellipticKofm, yShift);
    if (asinOfSnShiftedOfrResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }

    result.am = n * deltaY + asinOfSnShiftedOfrResult.val;
    result.status = SUCCESS;
    return result;
}

EllamResult jacobiam(float u, float m) {
    EllamResult result;
    
    EllintResult ellintResult = ellint_Kcomp_mma(m, 1e-5, 1e-5);
    if (ellintResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float ellipticKofm = ellintResult.val;
    float xShift = ellipticKofm;
    
    ElljacResult ellipjResult = ellipj(ellipticKofm, m);
    if (ellipjResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    float yShift = asin(ellipjResult.sn);
    
    EllamResult intermediateResult = jacobiamShifted(u + ellipticKofm, m, ellipticKofm, yShift);
    if (intermediateResult.status != SUCCESS) {
        result.status = FAILURE;
        return result;
    }
    
    result.am = intermediateResult.am - yShift;
    result.status = SUCCESS;
    return result;
}

// A straightforward port of the GNU Scientific
// Library's implementation of Jacobi elliptic functions.
// Returns in order: sn, cn, dn, return code.
ElljacResult ellipj(float u, float m) {
    ElljacResult result;
    
    // For now, we only compute when m <= 1.0.
    if (fabs(m) > 1.0) {
        result.sn = 0.0;
        result.cn = 0.0;
        result.dn = 0.0;
        result.status = DOMAIN_ERROR;
        return result;
    } else if (fabs(m) < 2.0 * FLT_EPSILON) {
        // If m is ~0, the elliptic functions reduce.
        // These approximations can be read off from
        // the corresponding series expansions in m.
        result.sn = sin(u);
        result.cn = cos(u);
        result.dn = 1.0;
        result.status = SUCCESS;
        return result;
    } else if (fabs(m - 1.0) < 2.0 * FLT_EPSILON) {
        result.sn = tanh(u);
        result.cn = 1.0/cosh(u);
        result.dn = 1.0/cosh(u);
        result.status = SUCCESS;
        return result;
    } else {
        int status = SUCCESS;
        const int N = 16;
        float mu[16];
        float nu[16];
        float c[16];
        float d[16];
        float sin_umu, cos_umu, t, r;
        int n = 0;
        
        mu[0] = 1.0;
        nu[0] = sqrt(1.0 - m);
        
        while ( fabs(mu[n] - nu[n]) > 4.0 * FLT_EPSILON * fabs(mu[n] + nu[n]) ) {
            mu[n + 1] = 0.5 * (mu[n] + nu[n]);
            nu[n + 1] = sqrt(mu[n] * nu[n]);
            ++n;
            if (n >= N - 1) {
                status = MAXITER_ERROR;
                break;
            }
        }
        
        sin_umu = sin(u * mu[n]);
        cos_umu = cos(u * mu[n]);
        
        float sn, cn, dn;
        
        if (fabs(sin_umu) < fabs(cos_umu)) {
            t = sin_umu / cos_umu;
            
            c[n] = mu[n] * t;
            d[n] = 1.0;
            
            while (n > 0) {
                n--;
                c[n] = d[n + 1] * c[n + 1];
                r = (c[n + 1] * c[n + 1]) / mu[n + 1];
                d[n] = (r + nu[n]) / (r + mu[n]);
            }
            
            dn = sqrt(1.0 - m) / d[n];
            cn = dn * gsl_sign(cos_umu) / gsl_hypot(1.0, c[n]);
            sn = cn * c[n] / sqrt(1.0 - m);
        } else {
            t = cos_umu / sin_umu;
            
            c[n] = mu[n] * t;
            d[n] = 1.0;
            
            while (n > 0) {
                --n;
                c[n] = d[n + 1] * c[n + 1];
                r = (c[n + 1] * c[n + 1]) / mu[n + 1];
                d[n] = (r + nu[n]) / (r + mu[n]);
            }
            
            dn = d[n];
            sn = gsl_sign(sin_umu) / gsl_hypot(1.0, c[n]);
            cn = c[n] * sn;
        }
        result.sn = sn;
        result.cn = cn;
        result.dn = dn;
        result.status = status;
        return result;
    }
}

// A port of GSL's implementation of R_D. See Carlson
// "Compution Elliptic Integrals by Duplication" (1979).
EllintResult ellint_RD(float x, float y, float z, float errtol, float prec) {
    EllintResult result;
    const float lolim = 2.0 / pow(FLT_MAX, 2.0 / 3.0);
    const float uplim = pow(0.1 * errtol / FLT_MIN, 2.0 / 3.0);
    const int nmax = 10000;

    if (min(x, y) < 0.0 || min(x + y, z) < lolim) {
        result.status = DOMAIN_ERROR;
        return result;
    } else if (locMAX3(x, y, z) < uplim) {
        const float c1 = 3.0 / 14.0;
        const float c2 = 1.0 / 6.0;
        const float c3 = 9.0 / 22.0;
        const float c4 = 3.0 / 26.0;
        float xn = x;
        float yn = y;
        float zn = z;
        float sigma = 0.0;
        float power4 = 1.0;
        float ea, eb, ec, ed, ef, s1, s2;
        float mu, xndev, yndev, zndev;
        int n = 0;

        while (true) {
            float xnroot, ynroot, znroot, lamda;
            float epslon;
            mu = (xn + yn + 3.0 * zn) * 0.2;
            xndev = (mu - xn) / mu;
            yndev = (mu - yn) / mu;
            zndev = (mu - zn) / mu;
            epslon = locMAX3(fabs(xndev), fabs(yndev), fabs(zndev));
            if (epslon < errtol) break;
            xnroot = sqrt(xn);
            ynroot = sqrt(yn);
            znroot = sqrt(zn);
            lamda = xnroot * (ynroot + znroot) + ynroot * znroot;
            sigma += power4 / (znroot * (zn + lamda));
            power4 *= 0.25;
            xn = (xn + lamda) * 0.25;
            yn = (yn + lamda) * 0.25;
            zn = (zn + lamda) * 0.25;
            n++;
            if (n == nmax) {
                result.status = MAXITER_ERROR;
                return result;
            }
        }
        ea = xndev * yndev;
        eb = zndev * zndev;
        ec = ea - eb;
        ed = ea - 6.0 * eb;
        ef = ed + ec + ec;
        s1 = ed * (-c1 + 0.25 * c3 * ed - 1.5 * c4 * zndev * ef);
        s2 = zndev * (c2 * ef + zndev * (-c3 * ec + zndev * c4 * ea));
        result.val = 3.0 * sigma + power4 * (1.0 + s1 + s2) / (mu * sqrt(mu));
        result.err = prec * fabs(result.val);
        result.status = SUCCESS;
        return result;
    } else {
        result.status = DOMAIN_ERROR;
        return result;
    }
}

// Carlson symmetric form R_C
EllintResult ellint_RC(float x, float y, float errtol, float prec) {
    EllintResult result;
    const float lolim = 5.0 * FLT_MIN;
    const float uplim = 0.2 * FLT_MAX;
    const int nmax = 10000;

    if (x < 0.0 || y < 0.0 || x + y < lolim) {
        result.status = DOMAIN_ERROR;
        return result;
    } else if (max(x, y) < uplim) {
        const float c1 = 1.0 / 7.0;
        const float c2 = 9.0 / 22.0;
        float xn = x;
        float yn = y;
        float mu, sn, lamda, s;
        int n = 0;

        while (true) {
            mu = (xn + yn + yn) / 3.0;
            sn = (yn + mu) / mu - 2.0;
            if (fabs(sn) < errtol) break;
            lamda = 2.0 * sqrt(xn) * sqrt(yn) + yn;
            xn = (xn + lamda) * 0.25;
            yn = (yn + lamda) * 0.25;
            n++;
            if (n == nmax) {
                result.status = MAXITER_ERROR;
                return result;
            }
        }
        s = sn * sn * (0.3 + sn * (c1 + sn * (0.375 + sn * c2)));
        result.val = (1.0 + s) / sqrt(mu);
        result.err = prec * fabs(result.val);
        result.status = SUCCESS;
        return result;
    } else {
        result.status = DOMAIN_ERROR;
        return result;
    }
}

// A port of GSL's implementation of R_F.
EllintResult ellint_RF(float x, float y, float z, float errtol, float prec) {
    EllintResult result;
    const float lolim = 5.0 * FLT_MIN;
    const float uplim = 0.2 * FLT_MAX;
    const int nmax = 10000;

    if (x < 0.0 || y < 0.0 || z < 0.0) {
        result.status = DOMAIN_ERROR;
        return result;
    } else if (x + y < lolim || x + z < lolim || y + z < lolim) {
        result.status = DOMAIN_ERROR;
        return result;
    } else if (locMAX3(x, y, z) < uplim) {
        const float c1 = 1.0 / 24.0;
        const float c2 = 3.0 / 44.0;
        const float c3 = 1.0 / 14.0;
        float xn = x;
        float yn = y;
        float zn = z;
        float mu, xndev, yndev, zndev, e2, e3, s;
        int n = 0;

        while (true) {
            float epslon, lamda;
            float xnroot, ynroot, znroot;
            mu = (xn + yn + zn) / 3.0;
            xndev = 2.0 - (mu + xn) / mu;
            yndev = 2.0 - (mu + yn) / mu;
            zndev = 2.0 - (mu + zn) / mu;
            epslon = locMAX3(fabs(xndev), fabs(yndev), fabs(zndev));
            if (epslon < errtol) break;
            xnroot = sqrt(xn);
            ynroot = sqrt(yn);
            znroot = sqrt(zn);
            lamda = xnroot * (ynroot + znroot) + ynroot * znroot;
            xn = (xn + lamda) * 0.25;
            yn = (yn + lamda) * 0.25;
            zn = (zn + lamda) * 0.25;
            n++;
            if (n == nmax) {
                result.status = MAXITER_ERROR;
                return result;
            }
        }
        e2 = xndev * yndev - zndev * zndev;
        e3 = xndev * yndev * zndev;
        s = 1.0 + (c1 * e2 - 0.1 - c2 * e3) * e2 + c3 * e3;
        result.val = s / sqrt(mu);
        
        // Assuming a default precision level similar to GSL_PREC_DOUBLE
        result.err = prec * fabs(result.val);
        
        result.status = SUCCESS;
        return result;
    } else {
        result.status = DOMAIN_ERROR;
        return result;
    }
}

EllintResult ellint_RJ(float x, float y, float z, float p, float errtol, float prec) {
    EllintResult result;
    const float lolim = pow(5.0 * FLT_MIN, 1.0 / 3.0);
    const float uplim = 0.3 * pow(0.2 * FLT_MAX, 1.0 / 3.0);
    const int nmax = 10000;
    
    if (x < 0.0 || y < 0.0 || z < 0.0) {
        result.status = DOMAIN_ERROR;
        return result;
    } else if (x + y < lolim || x + z < lolim || y + z < lolim || p < lolim) {
        result.status = DOMAIN_ERROR;
        return result;
    } else if (locMAX4(x, y, z, p) < uplim) {
        const float c1 = 3.0 / 14.0;
        const float c2 = 1.0 / 3.0;
        const float c3 = 3.0 / 22.0;
        const float c4 = 3.0 / 26.0;
        float xn = x;
        float yn = y;
        float zn = z;
        float pn = p;
        float sigma = 0.0;
        float power4 = 1.0;
        float mu, xndev, yndev, zndev, pndev;
        float ea, eb, ec, e2, e3, s1, s2, s3;
        int n = 0;
        
        while (true) {
            float xnroot, ynroot, znroot;
            float lamda, alfa, beta;
            float epslon;
            EllintResult rcresult;
            mu = (xn + yn + zn + pn + pn) * 0.2;
            xndev = (mu - xn) / mu;
            yndev = (mu - yn) / mu;
            zndev = (mu - zn) / mu;
            pndev = (mu - pn) / mu;
            epslon = locMAX4(fabs(xndev), fabs(yndev), fabs(zndev), fabs(pndev));
            if (epslon < errtol) break;
            xnroot = sqrt(xn);
            ynroot = sqrt(yn);
            znroot = sqrt(zn);
            lamda = xnroot * (ynroot + znroot) + ynroot * znroot;
            alfa = pn * (xnroot + ynroot + znroot) + xnroot * ynroot * znroot;
            alfa = alfa * alfa;
            beta = pn * (pn + lamda) * (pn + lamda);
            rcresult = ellint_RC(alfa, beta, errtol, prec);
            if (rcresult.status != SUCCESS) {
                result.val = 0.0;
                result.err = 0.0;
                result.status = rcresult.status;
                return result;
            }
            sigma += power4 * rcresult.val;
            power4 *= 0.25;
            xn = (xn + lamda) * 0.25;
            yn = (yn + lamda) * 0.25;
            zn = (zn + lamda) * 0.25;
            pn = (pn + lamda) * 0.25;
            n++;
            if (n == nmax) {
                result.status = MAXITER_ERROR;
                return result;
            }
        }
        
        ea = xndev * (yndev + zndev) + yndev * zndev;
        eb = xndev * yndev * zndev;
        ec = pndev * pndev;
        e2 = ea - 3.0 * ec;
        e3 = eb + 2.0 * pndev * (ea - ec);
        s1 = 1.0 + e2 * (-c1 + 0.75 * c3 * e2 - 1.5 * c4 * e3);
        s2 = eb * (0.5 * c2 + pndev * (-c3 - c3 + pndev * c4));
        s3 = pndev * ea * (c2 - pndev * c3) - c2 * pndev * ec;
        result.val = 3.0 * sigma + power4 * (s1 + s2 + s3) / (mu * sqrt(mu));
        result.err = prec * fabs(result.val);
        result.status = SUCCESS;
        return result;
    } else {
        result.status = DOMAIN_ERROR;
        return result;
    }
}

// Complete elliptic integral of the first kind, K
EllintResult ellint_Kcomp(float m, float errtol, float prec) {
    return ellint_RF(0.0, 1.0 - m, 1.0, errtol, prec);
}

// Incomplete elliptic integral of the first kind, F
// The convention IS NOT THE SAME AS PYTHON OR
// MATHEMATICA. The difference is that they compute
// F(phi, k^2).
EllintResult ellint_F(float phi, float m, float errtol, float prec) {
    EllintResult result;

    // Angular reduction to -pi/2 < phi < pi/2
    float nc = floor(phi / M_PI_F + 0.5);
    float phi_red = phi - nc * M_PI_F;
    phi = phi_red;

    float sin_phi = sin(phi);
    float sin2_phi = sin_phi * sin_phi;
    float x = 1.0 - sin2_phi;
    float y = 1.0 - m * sin2_phi;

    EllintResult rf = ellint_RF(x, y, 1.0, errtol, prec);
    result.val = sin_phi * rf.val;
    result.err = FLT_EPSILON * fabs(result.val) + fabs(sin_phi * rf.err);

    if (nc != 0) {
        EllintResult rk = ellint_Kcomp(m, errtol, prec);  // Add extra terms from periodicity
        if (rk.status != SUCCESS) {
            result.status = rk.status;
            return result;
        }
        result.val += 2 * nc * rk.val;
        result.err += 2 * fabs(nc) * rk.err;
    }

    result.status = rf.status;
    return result;
}

// Complete elliptic integral of the second kind, Ecomp
// TODO: verify against gsl
EllintResult ellint_Ecomp(float m, float errtol, float prec) {
    EllintResult result;

    if (m >= 1.0) {
        result.status = DOMAIN_ERROR;
        return result;
    } else if (m >= 1.0 - sqrt(FLT_EPSILON)) {
        // [Abramowitz+Stegun, 17.3.36]
        const float y = 1.0 - m;
        const float a[] = {0.44325141463, 0.06260601220, 0.04757383546};
        const float b[] = {0.24998368310, 0.09200180037, 0.04069697526};
        const float ta = 1.0 + y * (a[0] + y * (a[1] + a[2] * y));
        const float tb = -y * log(y) * (b[0] + y * (b[1] + b[2] * y));
        result.val = ta + tb;
        result.err = 2.0 * FLT_EPSILON * result.val;
        result.status = SUCCESS;
        return result;
    } else {
        EllintResult rf = ellint_RF(0.0, 1.0 - m, 1.0, errtol, prec);
        EllintResult rd = ellint_RD(0.0, 1.0 - m, 1.0, errtol, prec);
        result.val = rf.val - m / 3.0 * rd.val;
        result.err = rf.err + m / 3.0 * rd.err;
        result.status = ERROR_SELECT_2(rf.status, rd.status);
        return result;
    }
}

// Incomplete elliptic integral of the second kind, E
EllintResult ellint_E(float phi, float m, float errtol, float prec) {
    EllintResult result;

    // Angular reduction to -pi/2 < phi < pi/2
    float nc = floor(phi / M_PI_F + 0.5);
    float phi_red = phi - nc * M_PI_F;
    phi = phi_red;

    const float sin_phi = sin(phi);
    const float sin2_phi = sin_phi * sin_phi;
    const float x = 1.0 - sin2_phi;
    const float y = 1.0 - m * sin2_phi;

    if (x < FLT_EPSILON) {
        EllintResult re = ellint_Ecomp(m, errtol, prec);
        result.val = 2 * nc * re.val + gsl_sign(sin_phi) * re.val;
        result.err = 2 * fabs(nc) * re.err + re.err;
        result.status = re.status;
        return result;
    } else {
        EllintResult rf = ellint_RF(x, y, 1.0, errtol, prec);
        EllintResult rd = ellint_RD(x, y, 1.0, errtol, prec);
        const float sin3_phi = sin2_phi * sin_phi;
        result.val = sin_phi * rf.val - m / 3.0 * sin3_phi * rd.val;
        result.err = FLT_EPSILON * fabs(sin_phi * rf.val);
        result.err += fabs(sin_phi * rf.err);
        result.err += m / 3.0 * FLT_EPSILON * fabs(sin3_phi * rd.val);
        result.err += m / 3.0 * fabs(sin3_phi * rd.err);
        int status = ERROR_SELECT_2(rf.status, rd.status);
        if (nc == 0) {
            result.status = status;
            return result;
        } else {
            EllintResult re = ellint_Ecomp(m, errtol, prec);
            result.val += 2 * nc * re.val;
            result.err += 2 * fabs(nc) * re.err;
            result.status = ERROR_SELECT_3(status, re.status, SUCCESS);
            return result;
        }
    }
}

// Complete elliptic integral of the third kind, Pcomp
EllintResult ellint_Pcomp(float m, float n, float errtol, float prec) {
    EllintResult result;

    if (m >= 1.0) {
        result.status = DOMAIN_ERROR;
        return result;
    } else {
        EllintResult rf = ellint_RF(0.0, 1.0 - m, 1.0, errtol, prec);
        EllintResult rj = ellint_RJ(0.0, 1.0 - m, 1.0, 1.0 + n, errtol, prec);
        result.val = rf.val - (n / 3.0) * rj.val;
        result.err = rf.err + fabs(n / 3.0) * rj.err;
        result.status = ERROR_SELECT_2(rf.status, rj.status);
        return result;
    }
}

// Incomplete elliptic integral of the third kind, P
EllintResult ellint_P(float phi, float m, float n, float errtol, float prec) {
    EllintResult result;

    // Angular reduction to -pi/2 < phi < pi/2
    float nc = floor(phi / M_PI_F + 0.5);
    float phi_red = phi - nc * M_PI_F;
    phi = phi_red;

    const float sin_phi = sin(phi);
    const float sin2_phi = sin_phi * sin_phi;
    const float sin3_phi = sin2_phi * sin_phi;
    const float x = 1.0 - sin2_phi;
    const float y = 1.0 - m * sin2_phi;

    EllintResult rf = ellint_RF(x, y, 1.0, errtol, prec);
    EllintResult rj = ellint_RJ(x, y, 1.0, 1.0 + n * sin2_phi, errtol, prec);
    result.val = sin_phi * rf.val - n / 3.0 * sin3_phi * rj.val;
    result.err = FLT_EPSILON * fabs(sin_phi * rf.val);
    result.err += fabs(sin_phi * rf.err);
    result.err += n / 3.0 * FLT_EPSILON * fabs(sin3_phi * rj.val);
    result.err += n / 3.0 * fabs(sin3_phi * rj.err);
    int status = ERROR_SELECT_2(rf.status, rj.status);
    if (nc == 0) {
        result.status = status;
        return result;
    } else {
        EllintResult rp = ellint_Pcomp(m, n, errtol, prec);
        result.val += 2 * nc * rp.val;
        result.err += 2 * fabs(nc) * rp.err;
        result.status = ERROR_SELECT_3(status, rj.status, rp.status);
        return result;
    }
}

/*
 * The GSL's implementation differs in convention from that of Mathematica.
 * Here we provide interfaces to Mathematica's conventions.
 */
EllintResult ellint_F_mma(float phi, float m, float errtol, float prec) {
    return ellint_F(phi, m, errtol, prec);
}

EllintResult ellint_E_mma(float phi, float m, float errtol, float prec) {
    return ellint_E(phi, m, errtol, prec);
}

EllintResult ellint_P_mma(float phi, float m, float n, float errtol, float prec) {
    return ellint_P(phi, m, -1.0 * n, errtol, prec);
}

EllintResult ellint_Kcomp_mma(float m, float errtol, float prec) {
    return ellint_Kcomp(m, errtol, prec);
}

float normalizeAngle(float phi) {
    float twoPi = 2.0 * M_PI_F;
    float modPhi = fmod(phi, twoPi);

    // If the result is negative, add 2π to ensure it is in the range [0, 2π)
    if (modPhi < 0) {
        modPhi += twoPi;
    }

    return modPhi;
}

bool fEqual(float x, float y) {
    return fabs(x - y) < FLT_EPSILON ? true : false;
}

float3 sphericalToCartesian(float3 sphericalCoords) {
    float r     = sphericalCoords.x;
    float theta = sphericalCoords.y;
    float phi   = sphericalCoords.z;
    
    return float3(r * sin(theta) * cos(phi), 
                  r * sin(theta) * sin(phi),
                  r * cos(theta));
}

float3 cartesianToSpherical(float3 cartesianCoords) {
    float x = cartesianCoords.x;
    float y = cartesianCoords.y;
    float z = cartesianCoords.z;
    
    float r = sqrt(x*x + y*y + z*z);
    float theta = acos(z / r);
    float phi = atan2(y, x);
    
    return float3(r, theta, phi);
}

// Obtain the spherical coordinates of vs in the rotated frame in which
// vo's line of sight is the x axis and z axis is the original z axis
// projected into the plane defined by line of sight. 
float3 rotateSphericalCoordinate(float3 vsSpherical, float3 voSpherical) {
    float3 vsCartesian = sphericalToCartesian(vsSpherical);
    float3 voCartesian = sphericalToCartesian(voSpherical);
    
    float3 zhat = float3(0.0, 0.0, 1.0);

    float3 n1 = vsCartesian / length(vsCartesian);
    
    float3 v2 = zhat - dot(zhat, n1) * n1;
    float3 n2;
    if (fEqual(length(v2), 0.0)) {
        // When polar observer, n2 = 0 -> degenerate, arbitrary
        // up direction, just pick one in the plane.
        n2 = float3(0.0, 1.0, 0.0);
    } else {
        n2 = v2 / length(v2);
    }
    
    float3 n3 = cross(n2, n1);
    
    // This is just matrix multiplication by the matrix
    // whose rows are {n1, n3, n2}.
    float3 voHatCartesian = float3(dot(n1, voCartesian),
                                   dot(n3, voCartesian),
                                   dot(n2, voCartesian));
    
    return cartesianToSpherical(voHatCartesian);
}
