import re,os
BS=chr(92)
src=open('../../../components/STOBE/Stobe.vcxproj','rb').read().decode('utf-8-sig')
cm=open('CMakeLists.txt').read()
block=re.search(r'add_library\(Stobe SHARED(.*?)\)',cm,re.S).group(1)
files=re.findall(r'(src|legacy-v1)/([A-Za-z0-9_]+)\.cpp',block)
have=set(re.findall(r'ClCompile Include="'+re.escape(BS)+r'?src'+re.escape(BS)+r'+([A-Za-z0-9_]+)\.cpp"',src))
add=[n for d,n in files if d=='src' and n not in have]
print('add src:',add)
hdrs=set(re.findall(r'ClInclude Include="src'+re.escape(BS)+r'+([A-Za-z0-9_]+\.h)"',src))
newh=[h for h in sorted(os.listdir('src')) if h.endswith('.h') and h not in hdrs and not os.path.exists('../../../components/STOBE/src/'+h)]
print('new headers:',len(newh))
nl='\r\n'
cl=''.join('    <ClCompile Include="src%s%s.cpp" />%s'%(BS,n,nl) for n in add)
legacy=''.join('    <ClCompile Include="legacy-v1%s%s.cpp"><ObjectFileName>$(IntDir)v1%s%%(Filename).obj</ObjectFileName><AdditionalIncludeDirectories>legacy-v1;%%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories></ClCompile>%s'%(BS,n,BS,nl) for d,n in files if d=='legacy-v1')
ci=''.join('    <ClInclude Include="src%s%s" />%s'%(BS,h,nl) for h in newh)
a1='    <ClCompile Include="src'+BS+'NpcReferralPeople.cpp" />'+nl
assert a1 in src
src=src.replace(a1,cl+legacy+a1,1)
a2='    <ClInclude Include="src'+BS+'NativePlaceKnowledge.h" />'+nl
assert a2 in src
src=src.replace(a2,a2+ci,1)
open('Stobe.vcxproj','wb').write(b'\xef\xbb\xbf'+src.encode('utf-8'))
b=open('CMakeLists.txt','rb').read().replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
open('CMakeLists.txt','wb').write(b)
