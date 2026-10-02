#!/usr/bin/env python3
"""Pinned JDK21/IANA parser differential; --check needs no JDK or siblings.
Python standard library only; production tables never consult these goldens.
"""
import argparse,hashlib,importlib.util,json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
JAVA_SOURCE=ROOT/'Reference/language-range-oracle/IanaLanguageEquivalents.java'
JAVA_SOURCE_SHA='9d11a1ce46ba506c4b4286bc804919ab31b22179d882d99047f6f75b1c680992'
JAVA_COMMIT='63b63e47c982f7a87873c52ac2289cc0392f3329'
GOLDENS=ROOT/'Reference/language-range-goldens.json'
GOLDENS_SHA='2ce290f0f3bd2176b98416f4cc20c33ecd0fd192973e3b487262018edc47d73f'
ORACLE=r'''
package com.lokalized;
import java.util.*;import java.io.*;import java.nio.charset.StandardCharsets;
public class SwiftRangeOracle {
 static String hex(String s){return HexFormat.of().formatHex(s.getBytes(StandardCharsets.UTF_8));}
 static String bits(double d){return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits(d));}
 static String member(Locale.LanguageRange r){return hex(r.getRange())+"@"+bits(r.getWeight());}
 public static void main(String[]a)throws Exception{
 if(!System.getProperty("java.version").equals("21.0.11")||!System.getProperty("java.vendor").equals("Amazon.com Inc."))throw new IllegalStateException("Wrong JDK");
 var reader=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.US_ASCII));
 for(String line;(line=reader.readLine())!=null;){var f=line.split("\\t",-1);String text=new String(HexFormat.of().parseHex(f[1]),StandardCharsets.UTF_8);
  try{switch(f[0]){
  case "constructor":System.out.println("C\t"+member(new Locale.LanguageRange(text,Double.longBitsToDouble(Long.parseUnsignedLong(f[2],16)))));break;
  case "lowercase":System.out.println("L\t"+hex(text.toLowerCase(Locale.ROOT)));break;
  case "weight":System.out.println("W\t"+bits(Double.parseDouble(text)));break;
  case "iana":case "jdk":var ranges=f[0].equals("iana")?IanaLanguageEquivalents.parse(text):Locale.LanguageRange.parse(text);StringJoiner j=new StringJoiner(",");for(var r:ranges)j.add(member(r));System.out.println("P\t"+j);break;
  default:throw new IllegalArgumentException("bad mode");}
  }catch(RuntimeException e){System.out.println("E\t"+e.getClass().getSimpleName()+"\t"+hex(e.getMessage()));}
 }
 }
}
'''
DRIVER=r'''
func hex(_ text:String)->String {text.utf8.map {let s=String($0,radix:16);return s.count==1 ? "0"+s:s}.joined()}
func unhex(_ text:Substring)->String {var bytes:[UInt8]=[];var i=text.startIndex;while i<text.endIndex {let e=text.index(i,offsetBy:2);bytes.append(UInt8(text[i..<e],radix:16)!);i=e};return String(decoding:bytes,as:UTF8.self)}
func bits(_ value:Double)->String {let s=String(value.bitPattern,radix:16);return String(repeating:"0",count:16-s.count)+s}
func member(_ r:LanguageRange)->String {hex(r.range)+"@"+bits(r.weight)}
while let line=readLine() {
 let f=line.split(separator:"\t",omittingEmptySubsequences:false);let text=unhex(f[1])
 do {switch f[0] {
 case "constructor":print("C\t"+member(try LanguageRange(text,weight:Double(bitPattern:UInt64(f[2],radix:16)!))))
 case "lowercase":print("L\t"+hex(LanguageRangeLowercase.apply(text)))
 case "weight":if let value=LanguageRangeWeight.parse(text){print("W\t"+bits(value))}else{print("E\tNumberFormatException\t"+hex("For input string: \""+text+"\""))}
 case "iana","jdk":print("P\t"+(try LanguageRangeParser.parse(text,equivalents:f[0]=="jdk" ? .jdk:.ianaRegistry)).map(member).joined(separator:","))
 default:preconditionFailure("bad mode")}
 }catch let e as LanguageRangeError {print("E\t"+(e.kind == .indexOutOfBounds ? "ArrayIndexOutOfBoundsException":"IllegalArgumentException")+"\t"+hex(e.message))}
 catch {preconditionFailure(String(describing:error))}
}
'''

def sha(b):return hashlib.sha256(b).hexdigest()
def run(cmd,input=None):
 p=subprocess.run(cmd,input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 if p.returncode:raise RuntimeError(str(cmd)+'\n'+p.stderr.decode(errors='replace'))
 return p.stdout

def generator():
 p=ROOT/'Tools/generate_language_range_data.py';spec=importlib.util.spec_from_file_location('range_generator',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def samples(full):
 result=set()
 def add(mode,text,weight='3ff0000000000000'):result.add((mode,text,weight))
 iana=json.loads((ROOT/'Reference/iana-language-equivalences.json').read_bytes())
 jdk=json.loads((ROOT/'Reference/jdk-language-range-data.json').read_bytes())
 keys=set(jdk['languageEquivalents'])|{key for group in iana['languageEquivalenceClasses']for key in group}
 suffixes=['','-us','-de','-heploc','-x-de','-a-foo-de','-*-de'] if full else ['']
 for key in keys:
  for suffix in suffixes:
   for mode in ['iana','jdk']:add(mode,key+suffix)
 pairs=iana['regionVariantEquivalents']
 bases=['de','fr','ja','iw','sgn-be-fr','zh-cmn','x','*']
 if full:bases=sorted(keys|set(bases))
 for base in bases:
  for old,new in pairs:
   for mode in ['iana','jdk']:
    add(mode,base+old)
    if full:
     add(mode,base+old+new)
     add(mode,base+'-a-foo'+old)
     add(mode,base+'-*'+old)
 headers=['',' ', ',',',,,','fr,','fr,,',',fr','fr,,en','ACCEPT-LANGUAGE: IW;q=.9,HE;q=.4','he;q=.4,iw;q=.9',
  'en;q=0.4,de;q=0.4,fr;q=0.5','sgn-BE-FR','de-DE','ja-heploc','fr-FR','yol','fr;q=NaN','fr;q=Infinity','fr;q=1f',
  'fr;q=0x1p-1','fr;q=0x.8p0','fr;q=+1d','fr;q=1e-3','fr;q=-0','fr;q=-1e-99999','fr;q=1e9999','fr;q=1.1',
  'fr;q=0x1p0f','fr;q=1e-324','fr;q=2.2250738585072012e-308','fr;q=4.9406564584124654e-324',
  'fr;q=0x0.0000000000001p-1022','fr;q=1;q=0','fr;q=1,fr;q=2','fr;q=1,fr;q=bad','--','-','en-','en--us','*','*-US',
  'x-foo-*','a-1','not a header!','de;q=.8,\tfr;q=.9','fr;q=\t0.5\n','fr;q=\u00a00.5','fr;Q=0.7','fr;q=',
  'fr;q=0x10','fr;q=0x1p','fr;q=.','fr;q=1fd','fr;q=nan','fr;q=+infinity','fr;q=0.99999999999999999999999999999999999999',
  'a,\u0301b','accept-language:\u0301fr','fr;\u0301q=1','a\u212a','\u212a','\u0130','\u1c89','\u03a3', 'A\u03a3',
  ','.join('a'+chr(97+i//26)+chr(97+i%26)for i in range(300))]
 for header in headers:
  for mode in ['iana','jdk']:add(mode,header)
 constructor=['','-','---','en-','en--us','1en','a-1','a-*','*','x-foo-*','ABCDEFGH-12345678','abcdefghi','\u212a','\u0130','\u03a3','A\u03a3','A.\u03a3','A-\u03a3']
 weights=['0000000000000000','8000000000000000','3ff0000000000000','3fe0000000000000','3ff0000000000001','bff0000000000000','7ff0000000000000','fff0000000000000','7ff8000000000000','7ff0000000000001']
 for text in constructor:
  for weight in weights:add('constructor',text,weight)
 # Unicode15 scalar casing archive covers every changed scalar; Sigma context
 # matrix spans letters, numbers, marks, format, word/number punctuation and CJK.
 changed=[cp for cp,_ in jdk['scalarLowercase']]if full else [65,0x130,0x3a3,0x212a,0x1c89,0x2c00,0x10400]
 for cp in changed:add('lowercase',chr(cp))
 contexts=['','A','a','1','\u2160','\u0345','\u0301','\u200d',' ','-','--','.',"'",'"',',','%','#','$','\u00a2','\u0964','\u0965','\u4e00','\u3042','\u30a2','\u2027','\u00ad','\u03a3','\u02b0']
 for before in contexts:
  for after in contexts:
   for lead in ['','A']:
    for tail in ['','A'] if full else ['']:
     add('lowercase',lead+before+'\u03a3'+after+tail)
 if full:
  # Every observed property-range endpoint participates in contextual sigma.
  for low,high,mask in jdk['wordPropertyRanges']:
   for cp in [low,high]:
    for before,after in [('A'+chr(cp),''),('A',chr(cp)),('A'+chr(cp),'A'),('A',chr(cp)+'A')]:add('lowercase',before+'\u03a3'+after)
 for text in ['A\u03a3\U00010400','A\u03a3\U00010107A','A\u03a3\U000e0020A','A\U00010400\u03a3','A\u03a3\U0001d165A']:
  add('lowercase',text)
 for text in ['0','-0','+1','1f','1d','0x1p-1','0x.8p0','1e-99999','1e99999','0x1p99999','0x1p-99999','NaN','+NaN','-NaN','Infinity','-Infinity','\t.5\n','0.99999999999999999999','4.9406564584124654e-324','0x1.00000000000008p-1']:
  add('weight',text)
 return sorted(result)

def inputs(rows):return ''.join(mode+'\t'+text.encode().hex()+'\t'+weight+'\n'for mode,text,weight in rows).encode()
def compile_swift(scratch,swiftc):
 main=scratch/'main.swift';main.write_text(DRIVER);exe=scratch/'range-check'
 sources=[ROOT/'Sources/Lokalized/Numeric/JavaFloatingPoint.swift',ROOT/'Sources/Lokalized/API/LanguageRange.swift',ROOT/'Sources/Lokalized/API/LanguageRangeEquivalents.swift',ROOT/'Sources/Lokalized/Data/LanguageRangeTables.swift',*sorted((ROOT/'Sources/Lokalized/LanguageRanges').glob('*.swift'))]
 run([swiftc,'-O','-swift-version','6','-package-name','Lokalized','-module-cache-path',str(scratch/'module-cache'),*map(str,sources),str(main),'-o',str(exe)])
 return exe,sha(b''.join(p.read_bytes()for p in sources))
def main():
 p=argparse.ArgumentParser(description=__doc__);m=p.add_mutually_exclusive_group(required=True);m.add_argument('--check',action='store_true');m.add_argument('--oracle',action='store_true');m.add_argument('--refresh-goldens',action='store_true');p.add_argument('--jdk',type=Path);p.add_argument('--swiftc',default='swiftc');p.add_argument('--report',type=Path);a=p.parse_args()
 gen=generator();version=None
 if sha(JAVA_SOURCE.read_bytes())!=JAVA_SOURCE_SHA:raise RuntimeError('Java parser source archive pin differs')
 if not a.check:
  if a.jdk is None:raise RuntimeError('Explicit --jdk required')
  version=gen.verify_jdk(a.jdk.resolve())
 if a.check:
  raw=GOLDENS.read_bytes()
  if sha(raw)!=GOLDENS_SHA:raise RuntimeError('Range golden digest differs')
  archive=json.loads(raw);rows=[(e['mode'],e['text'],e['weightBits'])for e in archive['samples']];expected=[e['result']for e in archive['samples']]
  if rows!=samples(False)or archive['jdkReleaseSHA256']!=gen.RELEASE_SHA or archive['javaParserSourceSHA256']!=JAVA_SOURCE_SHA or archive['oracleSourceSHA256']!=sha(ORACLE.encode())or archive['jdkOptions']!=['-XX:-OmitStackTraceInFastThrow']:raise RuntimeError('Range golden inventory/provenance differs')
 else:rows=samples(a.oracle)
 data=inputs(rows)
 with tempfile.TemporaryDirectory(prefix='lokalized-range-diff-')as d:
  scratch=Path(d);exe,source_sha=compile_swift(scratch,a.swiftc)
  if not a.check:
   (scratch/'IanaLanguageEquivalents.java').write_bytes(JAVA_SOURCE.read_bytes());(scratch/'SwiftRangeOracle.java').write_text(ORACLE)
   run([str(a.jdk/'bin/javac'),'-d',str(scratch),str(scratch/'IanaLanguageEquivalents.java'),str(scratch/'SwiftRangeOracle.java')])
   expected=run([str(a.jdk/'bin/java'),'-XX:-OmitStackTraceInFastThrow','-cp',str(scratch),'com.lokalized.SwiftRangeOracle'],data).decode().splitlines()
  actual=run([str(exe)],data).decode().splitlines()
  if len(actual)!=len(rows)or len(expected)!=len(rows):raise RuntimeError('Range observation count differs')
  differences=[{'input':row,'actual':x,'expected':y}for row,x,y in zip(rows,actual,expected)if x!=y]
  if differences:raise RuntimeError(str(len(differences))+' differences: '+json.dumps(differences[:30],ensure_ascii=True))
  if a.refresh_goldens:
   archive={'formatVersion':1,'jdkReleaseSHA256':gen.RELEASE_SHA,'jdkVersionOutput':version,'jdkOptions':['-XX:-OmitStackTraceInFastThrow'],'javaCommit':JAVA_COMMIT,'javaParserSourceSHA256':JAVA_SOURCE_SHA,'oracleSourceSHA256':sha(ORACLE.encode()),'samples':[{'mode':mode,'text':text,'weightBits':weight,'result':result}for (mode,text,weight),result in zip(rows,expected)]}
   raw=(json.dumps(archive,indent=2,ensure_ascii=True)+'\n').encode();GOLDENS.write_bytes(raw);print('Golden SHA256',sha(raw),'samples',len(rows))
  report={'formatVersion':1,'passed':len(rows),'failed':0,'mode':'goldens'if a.check else'oracle','inputSHA256':sha(data),'outputSHA256':sha(('\n'.join(actual)+'\n').encode()),'productionSourcesSHA256':source_sha,'jdkReleaseSHA256':gen.RELEASE_SHA,'jdkOptions':['-XX:-OmitStackTraceInFastThrow'],'javaParserCommit':JAVA_COMMIT,'javaParserSourceSHA256':JAVA_SOURCE_SHA,'jdkVersionOutput':version,'swiftVersion':run([a.swiftc,'--version']).decode(),'operationCounts':{mode:sum(r[0]==mode for r in rows)for mode in ['iana','jdk','constructor','lowercase','weight']}}
  if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
  print(json.dumps(report,sort_keys=True))
if __name__=='__main__':
 try:main()
 except(OSError,ValueError,RuntimeError,KeyError)as e:print('Range verification refused:',e,file=sys.stderr);sys.exit(1)
