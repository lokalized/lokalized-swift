#!/usr/bin/env python3
"""Generate/check pinned IANA/JDK21 range and Unicode15 lowercase Swift data.
Normal check/refresh: Python standard library, archived bytes only.
Explicit --capture-jdk requires the exact local Corretto home; never downloads.
"""
import argparse, hashlib, json, re, subprocess, sys, tempfile, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
IANA_SHA = "2398b866e6739ae81d9484da929567e68e8255fe31aefe5bf2ef25846c611462"
JDK_DATA_SHA = "cfa23bf8a516c91a33d22376125b0f93c361d729e094f08d84c57c289fbf1b95"
RELEASE_SHA = "31c8dd26f07b2bd2c394663b57a93879ea139f525c76c730b13956890c151239"
SOURCE_PINS = {
 "java.base/java/util/Locale.java": "109224fce3f8be21ae0c5f58603e5f6504a0f2b674cb3dea343f06eb7b0164ee",
 "java.base/sun/util/locale/LocaleMatcher.java": "bf91cee65177dfb80c4d775d13a0a5e41c305bb6056e044a630115d8057943b3",
 "java.base/sun/util/locale/LocaleEquivalentMaps.java": "1a3aa245edae10c3dfe4657ae0b9d0b7d414597aca0f6d2876c9f5d7be33bb11",
 "java.base/java/lang/ConditionalSpecialCasing.java": "334839257c384ac3cb7971a7c8cccf070b2e2e87743011ab424d15af6d1974e1",
 "java.base/sun/text/resources/BreakIteratorRules.java": "7b4a1dd9fc02bcc0f7885209ffc4f462467631d2cddfa395f6bc7d6772300aae",
}
CAPTURE = r'''
import java.util.*;
import java.text.*;
import java.lang.reflect.*;
class RangeDataCapture {
 static BreakIterator bi=BreakIterator.getWordInstance(Locale.ROOT);
 static boolean joined(String a,String s,String b) {bi.setText(a+s+b);for(int i=bi.first();i!=BreakIterator.DONE;i=bi.next())if(i==a.length()||i==a.length()+s.length())return false;return true;}
 static boolean attached(String a,String s) {bi.setText(a+s);for(int i=bi.first();i!=BreakIterator.DONE;i=bi.next())if(i==a.length())return false;return true;}
 public static void main(String[] args)throws Exception {
  if(!System.getProperty("java.version").equals("21.0.11")||!System.getProperty("java.vendor").equals("Amazon.com Inc."))throw new IllegalStateException("wrong JDK");
  Class<?> maps=Class.forName("sun.util.locale.LocaleEquivalentMaps");
  TreeMap<String,List<String>> rows=new TreeMap<>();
  for(String name:List.of("singleEquivMap","multiEquivsMap")) {
   Field f=maps.getDeclaredField(name);f.setAccessible(true);
   for(var e:((Map<?,?>)f.get(null)).entrySet()) {List<String> v=new ArrayList<>();if(e.getValue() instanceof String s)v.add(s);else v.addAll(Arrays.asList((String[])e.getValue()));rows.put((String)e.getKey(),v);}
  }
  for(var e:rows.entrySet())System.out.println("E\t"+e.getKey()+"\t"+String.join(" ",e.getValue()));
  Field region=maps.getDeclaredField("regionVariantEquivMap");region.setAccessible(true);
  for(var e:((Map<?,?>)region.get(null)).entrySet())System.out.println("R\t"+e.getKey()+"\t"+e.getValue());
  Method cased=Class.forName("java.lang.ConditionalSpecialCasing").getDeclaredMethod("isCased",int.class);cased.setAccessible(true);
  int begin=0,lastMask=0;
  for(int cp=0;cp<=0x10ffff;cp++) {
   int mask=0;
   if(cp<0xd800||cp>0xdfff) {
    int t=Character.getType(cp);String s=new String(Character.toChars(cp));String lower=s.toLowerCase(Locale.ROOT);
    if(!s.equals(lower)) {StringJoiner j=new StringJoiner(" ");lower.codePoints().forEach(c->j.add(Integer.toHexString(c)));System.out.println("C\t"+Integer.toHexString(cp)+"\t"+j);}
    if((t>=1&&t<=5)||t==8) {if(joined("a",s,"a"))mask|=1;}
    if(t>=9&&t<=11)mask|=2;
    if(t==6||t==7)mask|=4;
    if(t==16)mask|=8;
    if(t==20||t==23||t==24||t==25||t==26||t==27||t==28||t==29||t==30||cp==0xad) {
     if(joined("a",s,"a"))mask|=16;
     if(joined("1",s,"1"))mask|=32;
     bi.setText(s+"1");if(!bi.isBoundary(s.length()))mask|=64;
     if(attached("1",s))mask|=128;
     if(attached("a",s))mask|=256;
    }
    if((Boolean)cased.invoke(null,cp))mask|=512;
   }
   if(mask!=lastMask) {if(lastMask!=0)System.out.println("W\t"+Integer.toHexString(begin)+"\t"+Integer.toHexString(cp-1)+"\t"+Integer.toHexString(lastMask));begin=cp;lastMask=mask;}
  }
  if(lastMask!=0)System.out.println("W\t"+Integer.toHexString(begin)+"\t10ffff\t"+Integer.toHexString(lastMask));
 }
}
'''

def digest(b): return hashlib.sha256(b).hexdigest()
def run(cmd):
 p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 if p.returncode:raise RuntimeError(p.stderr.decode(errors="replace"))
 return p

def verify_jdk(jdk):
 if digest((jdk/"release").read_bytes())!=RELEASE_SHA:raise RuntimeError("Wrong pinned JDK release")
 with zipfile.ZipFile(jdk/"lib/src.zip") as z:
  for name,sha in SOURCE_PINS.items():
   if digest(z.read(name))!=sha:raise RuntimeError("Wrong JDK source: "+name)
 version=run([str(jdk/"bin/java"),"-version"]).stderr.decode()
 if '"21.0.11"' not in version or "Corretto-21.0.11.10.1" not in version:raise RuntimeError("Wrong running JDK build")
 return version

def capture(jdk,output):
 version=verify_jdk(jdk)
 with tempfile.TemporaryDirectory(prefix="lokalized-range-data-")as d:
  p=Path(d)/"RangeDataCapture.java";p.write_text(CAPTURE)
  lines=run([str(jdk/"bin/java"),"--add-opens=java.base/sun.util.locale=ALL-UNNAMED","--add-opens=java.base/java.lang=ALL-UNNAMED",str(p)]).stdout.decode().splitlines()
 maps={};regions=[];cases=[];words=[]
 for line in lines:
  fields=line.split("\t")
  if fields[0]=="E":maps[fields[1]]=fields[2].split(" ")
  elif fields[0]=="R":regions.append(fields[1:])
  elif fields[0]=="C":cases.append([int(fields[1],16),[int(x,16)for x in fields[2].split()]])
  elif fields[0]=="W":words.append([int(x,16)for x in fields[1:]])
  else:raise RuntimeError("Unknown captured data record")
 archive={"formatVersion":1,"jdk":{"version":"21.0.11","vendor":"Amazon.com Inc.","build":"Corretto-21.0.11.10.1","releaseSHA256":RELEASE_SHA,"sourcePins":SOURCE_PINS,"versionOutput":version},
          "jdkRegistryDate":"2025-05-15","unicodeVersion":"15.0","captureSourceSHA256":digest(CAPTURE.encode()),
          "languageEquivalents":maps,"regionVariantEquivalents":regions,"scalarLowercase":cases,"wordPropertyRanges":words,
          "wordProperties":{"letter":1,"number":2,"enclosing":4,"ignored":8,"middleWord":16,"middleNumber":32,"prefixNumber":64,"suffixNumber":128,"suffixWord":256,"cased":512}}
 raw=(json.dumps(archive,indent=2,ensure_ascii=True)+"\n").encode();output.write_bytes(raw)
 print("Captured data SHA256",digest(raw),"keys",len(maps),"caseMappings",len(cases),"wordRanges",len(words))

def blob(lines):
 data="".join(line+"\n"for line in lines);offsets=[0];position=0
 for line in lines:position+=len(line.encode())+1;offsets.append(position)
 if any(not re.fullmatch(r"[a-z0-9*=\- ]+",line)for line in lines):raise RuntimeError("Unsafe table row")
 chunks=data.splitlines(keepends=True)
 quoted='\n'.join('        '+json.dumps(line)+(' +'if i+1<len(chunks)else'')for i,line in enumerate(chunks))
 # StaticString cannot concatenate literals; use one escaped ASCII literal.
 return json.dumps(data),offsets

def generate(iana,jdk):
 if iana["formatVersion"]!=1 or iana["registry"]["fileDate"]!="2026-09-17":raise RuntimeError("IANA version differs")
 if jdk["formatVersion"]!=1 or jdk["jdk"]["releaseSHA256"]!=RELEASE_SHA or jdk["jdk"]["sourcePins"]!=SOURCE_PINS:raise RuntimeError("JDK archive provenance differs")
 if jdk["captureSourceSHA256"]!=digest(CAPTURE.encode()):raise RuntimeError("Capture algorithm pin differs")
 if iana["regionVariantEquivalents"]!=jdk["regionVariantEquivalents"]:raise RuntimeError("Region/variant order differs from pinned JDK")
 maps={};seen=set()
 for group in iana["languageEquivalenceClasses"]:
  if len(group)<2 or len(set(group))!=len(group)or any(x in seen for x in group):raise RuntimeError("Invalid IANA class")
  seen.update(group)
  for key in group:maps[key]=[x for x in group if x!=key]
 lines=['// Generated by Tools/generate_language_range_data.py; do not edit.',
        '// IANA factual data; Unicode15 casing facts. See Documentation/LANGUAGE-RANGES.md.',
        'package enum LanguageRangeTables {',
        '    package static let registryDate = "2026-09-17"',f'    package static let registrySourceSHA256 = "{iana["registry"]["sha256"]}"',
        f'    package static let artifactSHA256 = "{IANA_SHA}"',f'    package static let jdkDataSHA256 = "{JDK_DATA_SHA}"',
        '    package static let jdkRegistryDate = "2025-05-15"','    package static let unicodeVersion = "15.0"']
 for name,data in [("registry",maps),("jdk",jdk["languageEquivalents"])]:
  rows=[key+"="+" ".join(data[key])for key in sorted(data)]
  encoded,offsets=blob(rows)
  lines.append(f'    package static let {name}Blob: StaticString = {encoded}')
  lines.append(f'    package static let {name}Offsets: [UInt32] = [{", ".join(map(str,offsets))}]')
 lines.append('    package static let regionVariantEquivalents: [(String, String)] = [')
 for a,b in iana['regionVariantEquivalents']:lines.append(f'        ({json.dumps(a)}, {json.dumps(b)}),')
 lines.append('    ]')
 mappings=jdk['scalarLowercase']
 if mappings!=sorted(mappings)or len({x[0]for x in mappings})!=len(mappings):raise RuntimeError('Invalid lowercase order')
 if any(len(v)not in(1,2)or any(not(0<=c<=0x10ffff)or 0xd800<=c<=0xdfff for c in v)for _,v in mappings):raise RuntimeError('Invalid lower scalar mapping')
 encoded=''.join(f'{key:06x}{value[0]:06x}{value[1]if len(value)==2 else 0xffffff:06x}'for key,value in mappings)
 lines.append(f'    package static let lowercaseBlob: StaticString = "{encoded}"')
 lines.append(f'    package static let lowercaseCount = {len(mappings)}')
 ranges=jdk['wordPropertyRanges'];prior=-1
 for lo,hi,mask in ranges:
  if not(prior<lo<=hi<=0x10ffff and 0<mask<1024):raise RuntimeError('Invalid word property range')
  prior=hi
 encoded=''.join(f'{lo:06x}{hi:06x}{mask:03x}'for lo,hi,mask in ranges)
 lines.append(f'    package static let wordBlob: StaticString = "{encoded}"')
 lines.append(f'    package static let wordRangeCount = {len(ranges)}')
 lines.append('}')
 return '\n'.join(lines)+'\n',{"registryKeys":len(maps),"jdkKeys":len(jdk['languageEquivalents']),"lowercaseMappings":len(mappings),"wordPropertyRanges":len(ranges)}

def main():
 p=argparse.ArgumentParser(description=__doc__);mode=p.add_mutually_exclusive_group(required=True)
 mode.add_argument('--check',action='store_true');mode.add_argument('--refresh',action='store_true');mode.add_argument('--capture-jdk',action='store_true')
 p.add_argument('--jdk',type=Path);p.add_argument('--reference',type=Path,default=ROOT/'Reference');p.add_argument('--output',type=Path,default=ROOT/'Sources/Lokalized/Data/LanguageRangeTables.swift');a=p.parse_args()
 archive=a.reference/'jdk-language-range-data.json'
 if a.capture_jdk:
  if a.jdk is None:raise RuntimeError('Explicit --jdk is required')
  capture(a.jdk.resolve(),archive);return
 ir=(a.reference/'iana-language-equivalences.json').read_bytes();jr=archive.read_bytes()
 if digest(ir)!=IANA_SHA or digest(jr)!=JDK_DATA_SHA:raise RuntimeError('Range input digest differs')
 source,report=generate(json.loads(ir),json.loads(jr));report['sourceBytes']=len(source.encode());report['sourceSHA256']=digest(source.encode())
 if a.refresh:a.output.write_text(source)
 elif a.output.read_bytes()!=source.encode():raise RuntimeError('Generated range data differs; explicit --refresh required')
 report['status']='refreshed'if a.refresh else'verified';print(json.dumps(report,sort_keys=True))
if __name__=='__main__':
 try:main()
 except(OSError,ValueError,RuntimeError,KeyError,zipfile.BadZipFile)as e:print('Range data refused:',e,file=sys.stderr);sys.exit(1)
