
## clear history
rm(list = ls(all = TRUE))
graphics.off()

## install and load packages
libraries = c("mgcv", "MASS")
lapply(libraries, function(x) if (!(x %in% installed.packages())) {
    install.packages(x)
})
lapply(libraries, library, quietly = TRUE, character.only = TRUE)

## count number of data points around each grid point
countdata = function(xdata, xgrid, h) {
    nsize      = length(xdata)
    gridlength = length(xgrid)
    ncount     = rep(0, gridlength)
    for (i in 1:gridlength) {
        xnhd      = ifelse(abs(xdata - xgrid[i]) <= h, 1, 0)
        ncount[i] = sum(xnhd)
    }
    ncount
}

# Epanechnikov kernel function
epkernel = function(x) {
    temp = 0.75 * (1 - x * x)
    temp[x <= -1] = 0
    temp[x >= 1]  = 0
    temp
}

# smoother matrix in Huang and Chen (2008) Epanechnikov kernel normlizing &
# symmatric & sum to one
proj.ep.symmetric = function(x, xgrid, h) {
    gridlength = length(xgrid)
    datalength = length(x)
    gridint    = xgrid[2] - xgrid[1]
    localproj  = matrix(0, ncol = datalength, nrow = datalength)
    bigK       = matrix(0, ncol = gridlength, nrow = datalength)
    for (i in 1:datalength) {
      bigK[i, ] = (epkernel(((x[i] - xgrid)/h))/h)
    }
    adjvect = as.numeric(1/bigK %*% rep(gridint, gridlength))
    bigKK   = (diag(adjvect, nrow = datalength, ncol = datalength) %*% bigK)
    
    for (i in 1:gridlength) {
        kweight   = diag(bigKK[, i], ncol = datalength)
        bigX      = cbind(rep(1, length(x)), (x - xgrid[i]))
        localH    = bigX %*% (solve(t(bigX) %*% kweight %*% bigX)) %*% t(bigX) %*% kweight
        localproj = localproj + kweight %*% localH
    }
    localproj  = localproj * gridint
    defree     = sum(diag(localproj))
    list(Hstar = localproj, defree = defree)
}

## analysis of deviance function for log (poisson) partially linear model
## using Epanechnikov kernel, xgrid must be equally spaced testing no
## effect of xt x1 x2 linear part xt nonparametric part
anodev.gplm.poisson.chisq = function(y, x1, x2, xt, tgrid, h) {
    g.glm = glm(y ~ x1 + x2 + xt, family = poisson(link = "log"))
    
    # get initial value for parameters
    bcoeff  = g.glm$coeff[2:3]
    g0.glm  = glm(y ~ x1 + x2, family = poisson(link = "log"))
    samplen = length(y)
    
    # normalizing weights integrated over tgrid to 1
    gridlength = length(tgrid)
    gridint    = tgrid[2] - tgrid[1]
    bigK       = matrix(0, ncol = gridlength, nrow = samplen)
    for (i in 1:samplen) {
      bigK[i, ] = (epkernel(((xt[i] - tgrid)/h))/h)
    }
    adjvect = as.numeric(1/bigK %*% rep(gridint, gridlength))
    bigKK   = (diag(adjvect, nrow = samplen, ncol = samplen) %*% bigK)
    
    # use local likelihood
    d4.dev    = rep(0, length(tgrid))
    d4.coeff  = matrix(0, nrow = length(tgrid), ncol = 2)
    d4.linear = matrix(0, ncol = length(tgrid), nrow = samplen)
    
    # iteration begins
    nitrt = 0
    bdiff = 100
    
    while ((bdiff > 0.001) & (nitrt < 30)) {
        nitrt = nitrt + 1
        
        for (j in 1:length(tgrid)) {
            xt.local = xt - tgrid[j]
            kweights = bigKK[, j]
            
            # keep parametric part fixed, and fit local linear for xt set maxit=5, it is
            # sufficient to update the values offset(I(1.3 * X1))
            d4.glm = glm(y ~ offset(bcoeff[1] * x1) + offset(bcoeff[2] * x2) + xt.local, 
                family = poisson(link = "log"), weights = kweights, control = glm.control(maxit = 5))
            
            d4.dev[j]      = d4.glm$dev
            d4.coeff[j, ]  = d4.glm$coeff
            d4.linear[, j] = (d4.glm$coeff[1] + d4.glm$coeff[2] * xt.local) * kweights
            
        }
        # j loop grid
        
        thetastar = (apply(d4.linear, 1, sum) * gridint)
        
        # keep nonparametric part fixed, and fit linear terms for x1 and x2 set maxit=5,
        # it is sufficient to update the values
        para.glm = glm(y ~ -1 + x1 + x2 + offset(thetastar), family = poisson(link = "log"), 
            control = glm.control(maxit = 5))
        
        bdiff  = sum(abs(para.glm$coeff - bcoeff))
        bcoeff = para.glm$coeff
    }
    # end of while
    
    # usually, the algorithm converges
    notconv = 0
    
    # if nitrt==30 then non-convergence
    if (nitrt == 30) {
        print("ERROR")
        notconv = 1
    }
    
    intDev    = sum(d4.dev) * gridint
    teststat0 = -(intDev - g0.glm$dev)
    
    d4.H      = proj.ep.symmetric(xt, tgrid, h)
    degfree   = d4.H$defree
    chipvalue = 1 - pchisq(teststat0, degfree - 1)
    
    list(intDev = intDev, teststat0 = teststat0, bcoeff = bcoeff, thetastar = thetastar, 
        degfree = degfree, chipvalue = chipvalue, notconv = notconv)
    
}

# partial linear exp POISSON a=0,1,2 exp a=0 n=100 seed(201506200) exp a=1 n=100
# set.seed(201506100) exp a=2 n=100 set.seed(201606100) exp a=0 n=200
# set.seed(20150831) exp a=1 n=200 set.seed(201508831) exp a=2 n=200
set.seed(201612831)

# partial linear cos POISSON a=0.5, 1.5 cos a=1.5 n=100 set.seed(20150619) cos
# a=1.5 n=200 set.seed(10216102) cos a=0.5 n=200 set.seed(20161201) cos a=0.5
# n=100 set.seed(201505293)

samplen = 200
Nsim    = 5000

# try 5 values of bandwidth
hchoice = c(0.15, 0.2, 0.25, 0.3, 0.4)
hlength = length(hchoice)
nlnrcov = 2

# grid points on [-0.5,1]
tgrid = seq(-0.5, 1, 0.005)  #length 301

# initialization
intD     = matrix(0, nrow = Nsim, ncol = hlength)
teststat = matrix(0, nrow = Nsim, ncol = hlength)
pvalue   = matrix(0, nrow = Nsim, ncol = hlength)
degfee   = matrix(0, nrow = Nsim, ncol = hlength)
mdiff    = matrix(0, nrow = Nsim, ncol = hlength)

# to check convergence
conv = matrix(1, nrow = Nsim, ncol = hlength)
bb   = matrix(0, nrow = Nsim, ncol = (nlnrcov * hlength))
mhat = matrix(0, nrow = samplen, ncol = (hlength * Nsim))
AICc = matrix(0, nrow = Nsim, ncol = hlength)

# set the initial value as the smallest bandwidth
AICch      = rep(0.15, Nsim)
AICcpvalue = rep(0.99999, Nsim)

# Horowitz and Spokoiny (2001) set the initial value as the smallest bandwidth
adaptiveh      = rep(0.15, Nsim)
adaptivepvalue = rep(0.99999, Nsim)
x2xtcorr       = rep(0, Nsim)

# for gam in mgcv
gam.p0  = rep(0, Nsim)
gam.p1  = rep(0, Nsim)
gam.pn  = rep(0, Nsim)
gam.edf = rep(0, Nsim)
gam.ts  = rep(0, Nsim)

a = 2
for (k in 1:Nsim) {
    
    checkdata = rep(0, length(tgrid))
    
    # to simulate correlated data rho=0.3
    varmat = matrix(c(1, 0.3, 0.3, 1), 2, 2)
    
    while (any(checkdata <= 5)) {
        xdata = mvrnorm(samplen, rep(0, 2), varmat)
        xtmp  = pnorm(xdata[, 2])
        xt    = 1.5 * (xtmp - min(xtmp))/(max(xtmp) - min(xtmp)) - 0.5
        
        # so that xt is unfirom on (-0.5,1) with min=-0.5 and max=1
        checkdata = countdata(xt, tgrid, 0.15)
    }
    x2         = 0.5 * xdata[, 1]
    x1         = ifelse((runif(samplen, -1, 1)) > 0, 1, -1)
    t.order    = order(xt)
    xt         = xt[t.order]
    x1         = x1[t.order]
    x2         = x2[t.order]
    incvec     = rep(1, samplen)
    xtt        = cbind(incvec, xt)
    proj.li.xt = xtt %*% (solve(t(xtt) %*% xtt)) %*% t(xtt)
    x1.th      = (diag(1, nrow = samplen, ncol = samplen) - proj.li.xt) %*% x1
    x2.th      = (diag(1, nrow = samplen, ncol = samplen) - proj.li.xt) %*% x2
    beta1      = 0.1
    beta2      = -0.1
    
    # specify truemt function exp or cos truemt = a*cos(2*pi*xt)
    truemt = a * exp(-16 * xt * xt)
    
    # plot(xt, truemt)
    eta = -1 + beta1 * x1.th + beta2 * x2.th + truemt
    
    # poisson
    lambda0     = exp(eta)
    y0          = as.integer(rpois(samplen, lambda0))
    x2xtcorr[k] = cor(x2, xt)
    d4          = data.frame(x1.th, x2.th, xt, y0)
    names(d4)   = c("x1.th", "x2.th", "xt", "y0")
    t.range     = max(xt) - min(xt)
    tgrid       = seq(-0.5, 1, 0.005)  #length 301
    AICcmin     = 10
    for (hi in 1:hlength) {
        h = hchoice[hi]
        
        # call the function
        semilogit = anodev.gplm.poisson.chisq(d4$y0, d4$x1.th, d4$x2.th, d4$xt, tgrid, 
            h)
        
        # proposed chi-square test statistic
        teststat[k, hi] = semilogit$teststat0
        intD[k, hi]     = semilogit$intDev
        pvalue[k, hi]   = semilogit$chipvalue
        mdiff[k, hi]    = sum((semilogit$thetastar - truemt)^2)/samplen
        # if non-convergent
        if (semilogit$notconv == 1) 
            conv[k, hi] = 0
        
        degfee[k, hi]                  = semilogit$degfree
        bb[k, ((hi * 2 - 1):(hi * 2))] = semilogit$bcoeff
        # b1, b2 for h=0.15, then b1, b2 for h=0.2, ...
        
        mhat[, ((k - 1) * hlength + hi)] = semilogit$thetastar
        # mhat for h1, h2, ... h5,
        
        # calculate AICc and find AICcmin
        AICc[k, hi] = log(intD[k, hi]/samplen) + 2 * (degfee[k, hi] + 1)/(samplen - 
            degfee[k, hi] - 2)
        if ((AICc[k, hi] < AICcmin) && (conv[k, hi] == 1)) {
            AICcmin  = AICc[k, hi]
            AICch[k] = h
        }
        # find the smallest pvalue based on Horowitz and Spokoiny (2001)
        if ((pvalue[k, hi] < adaptivepvalue[k]) && (conv[k, hi] == 1)) {
            adaptivepvalue[k] = pvalue[k, hi]
            adaptiveh[k]      = h
        }
        
    }
    # end hi bandiwdth
    if (any(conv[k, ] == 1)) {
        findaicc      = (hchoice == AICch[k])
        AICcpvalue[k] = pvalue[k, findaicc]
    } else {
        cat("all h values fail to converge\n")
    }
    
    # mgcv package
    b.gam      = gam(d4$y0 ~ d4$x1.th + d4$x2.th + s(d4$xt), method = "REML", family = poisson(link = "log"))
    gam.p0[k]  = summary(b.gam, p.type = 0)$s.pv
    gam.p1[k]  = summary(b.gam, p.type = 1)$s.pv
    gam.pn[k]  = summary(b.gam, p.type = -1)$s.pv
    gam.edf[k] = summary(b.gam)$edf
    gam.ts[k]  = summary(b.gam)$chi.sq
    
    cat(k, "/")
}
# k loop

testresults1 = round(matrix(c(hchoice, colSums(pvalue <= 0.05)/Nsim), nrow = 2, ncol = hlength, 
    byrow = TRUE), 6)
testresults1
testresults2 = round(matrix(c(mean(AICch), sd(AICch), sum(AICcpvalue < 0.05)/Nsim, 
    mean(adaptiveh), sd(adaptiveh), sum(adaptivepvalue < 0.05)/Nsim), nrow = 2, byrow = TRUE), 
    6)
testresults2

degresults = round(matrix(c(mean(degfee[, 1]), sd(degfee[, 1]), mean(degfee[, 2]), 
    sd(degfee[, 2]), mean(degfee[, 3]), sd(degfee[, 3]), mean(degfee[, 4]), sd(degfee[, 
        4]), mean(degfee[, 5]), sd(degfee[, 5])), nrow = 2, byrow = FALSE), 6)
degresults

print(table(AICch))
print(table(adaptiveh))

print("gam")
print(sum(gam.p0 <= 0.05))/Nsim
print(sum(gam.p1 <= 0.05))/Nsim
print(sum(gam.pn <= 0.05))/Nsim
print(summary(gam.edf))
print(sqrt(var(gam.edf)))

print(summary(x2xtcorr))

print(sd(x2xtcorr))


#### check convergence for fixed bandwidth

print(colSums(conv))

testresults3 = round(matrix(c(hchoice, ((colSums((pvalue * conv > 0) & (pvalue * 
    conv <= 0.05)))/colSums(conv))), nrow = 2, ncol = hlength, byrow = TRUE), 6)
print(testresults3)

#### chcek convergence for the smallest bandwidth

print(sum(conv[, 1]))
testresults4    = rep(0, hlength)
testresults4[1] = sum((pvalue[, 1] * conv[, 1]) <= 0.05)/sum(conv[, 1])
testresults4[2] = sum((pvalue[, 2] * conv[, 1]) <= 0.05)/sum(conv[, 1])
testresults4[3] = sum((pvalue[, 3] * conv[, 1]) <= 0.05)/sum(conv[, 1])
testresults4[4] = sum((pvalue[, 4] * conv[, 1]) <= 0.05)/sum(conv[, 1])
testresults4[5] = sum((pvalue[, 5] * conv[, 1]) <= 0.05)/sum(conv[, 1])
print(round(matrix(c(hchoice, testresults4), nrow = 2, ncol = hlength, byrow = TRUE), 
    6))
