import sys
# s2v.py dx hzs rollmode(c<val>|s<scale>) [hxo]: f5 keys variant
K=[(0.28,.1885,.1268,7.311,.0518,1.9071,-14),(.42,.1493,-.1807,8.209,.0018,1.0159,-27.5),(.52,.2427,-.8557,9.948,-.057,.0935,-23.9),(.62,.2856,-1.6181,9.613,-.0643,-.3604,-13.2),(.76,.1568,-1.9043,10.236,-.0881,-.9164,-19.4)]
dx=float(sys.argv[1]);hs=float(sys.argv[2]);rm=sys.argv[3];hxo=float(sys.argv[4]) if len(sys.argv)>4 else 0
out=[]
for t,hx,hy,hz,tx,ty,r in K:
    r=float(rm[1:]) if rm[0]=='c' else r*float(rm[1:])
    out.append('%.3f %.4f %.4f %.3f %.4f %.4f %g 0 0'%(t,hx+dx+hxo,hy,hz*hs,tx+dx,ty,r))
print('; '.join(out))
