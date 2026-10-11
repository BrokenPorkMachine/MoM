from pathlib import Path
import hashlib, plistlib
root=Path(__file__).resolve().parents[1]
out=root/'MacOnMac.xcodeproj/project.pbxproj'
def ID(s):return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s):return '"'+s.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')+'"'
def items(a):return '( '+', '.join(a)+', )' if a else '()'
obj={}
def add(k,body):
 key=ID(k)
 assert key not in obj
 obj[key]=body
 return key
# refs
refs={}
for subdir in ['App','Core','Helpers/VolumeBootDiskBroker','Privileged/VolumeBootRawDiskDaemon']:
 for f in sorted((root/subdir).glob('*.swift')):
  path=f.relative_to(root).as_posix()
  refs[path]=add('ref:'+path,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(f.name)}; sourceTree = "<group>";')
appProduct=add('product-app','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MacOnMac.app; sourceTree = BUILT_PRODUCTS_DIR;')
svcProduct=add('product-xpc','isa = PBXFileReference; explicitFileType = "wrapper.xpc-service"; includeInIndex = 0; path = MacOnMacDiskBroker.xpc; sourceTree = BUILT_PRODUCTS_DIR;')
dmnProduct=add('product-daemon','isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = MacOnMacRawDiskDaemon; sourceTree = BUILT_PRODUCTS_DIR;')
source_refs={}
def buildRef(target,path):
 key=target+':'+path
 if key not in source_refs:
  source_refs[key]=add('bf:'+key,'isa = PBXBuildFile; fileRef = '+refs[path]+';')
 return source_refs[key]
app_sources=[p for p in refs if p.startswith(('App/','Core/'))]
xpc_sources=['Helpers/VolumeBootDiskBroker/main.swift','Core/BrokerAuthorizationPolicy.swift','Core/BrokerProtocolContract.swift']
daemon_sources=['Privileged/VolumeBootRawDiskDaemon/main.swift','Privileged/VolumeBootRawDiskDaemon/TrustedDiskProbe.swift','Core/BrokerAuthorizationPolicy.swift','Core/DaemonBrokerContract.swift','Core/ReadOnlyGrantPolicy.swift','Core/PhysicalDiskTopologyProof.swift','Privileged/VolumeBootRawDiskDaemon/PhysicalDiskTopologyProbe.swift']
# groups
folders={}
for group,path in [('App','App/'),('Core','Core/'),('Helpers','Helpers/VolumeBootDiskBroker/'),('Privileged','Privileged/VolumeBootRawDiskDaemon/')]:
 children=[refs[p] for p in refs if p.startswith(path)]
 folders[group]=add('grp:'+group,'isa = PBXGroup; children = '+items(children)+'; path = '+q(path[:-1])+'; sourceTree = "<group>";')
resources=add('grp-res','isa = PBXGroup; children = (); path = Resources; sourceTree = "<group>";')
products=add('grp-prod','isa = PBXGroup; children = '+items([appProduct,svcProduct,dmnProduct])+'; name = Products; sourceTree = "<group>";')
rootGroup=add('grp-root','isa = PBXGroup; children = '+items([folders['App'],folders['Core'],folders['Helpers'],folders['Privileged'],resources,products])+'; sourceTree = "<group>";')
# fix nested group paths; Helpers and Privileged group path should be relative to root accurate
phases={}
for target,paths in [('MacOnMac',app_sources),('MacOnMacDiskBroker',xpc_sources),('MacOnMacRawDiskDaemon',daemon_sources)]:
 bf=[buildRef(target,p) for p in paths]
 phases[target]=add('phase:'+target,'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+items(bf)+'; runOnlyForDeploymentPostprocessing = 0;')
frameworks={}
for target in phases:
 frameworks[target]=add('frm:'+target,'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
# embed signed xpc, expect Xcode code-sign-on-copy
embedBF=add('embed-xpc-bf','isa = PBXBuildFile; fileRef = '+svcProduct+'; settings = { ATTRIBUTES = ( CodeSignOnCopy, RemoveHeadersOnCopy, ); };')
embed=add('embed-phase',f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ( {embedBF}, ); name = "Embed XPC Service"; runOnlyForDeploymentPostprocessing = 0;')
shell='''set -euo pipefail
OUT="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
mkdir -p "${OUT}/MacOS" "${OUT}/Library/LaunchDaemons"
cp "${BUILT_PRODUCTS_DIR}/MacOnMacRawDiskDaemon" "${OUT}/MacOS/VolumeBootRawDiskDaemon"
cp "${SRCROOT}/Resources/LaunchDaemons/ca.zensoftware.MacOnMac.RawDiskBroker.plist" "${OUT}/Library/LaunchDaemons/ca.zensoftware.MacOnMac.RawDiskBroker.plist"
'''
post=add('script-daemon','isa = PBXShellScriptBuildPhase; alwaysOutOfDate = 1; buildActionMask = 2147483647; files = (); inputPaths = (); name = "Bundle launchd daemon"; outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/bash; shellScript = '+q(shell)+';')
# dep
appT=ID('target-MacOnMac');svcT=ID('target-MacOnMacDiskBroker');dmnT=ID('target-MacOnMacRawDiskDaemon')
proxy1=add('proxy-xpc',f'isa = PBXContainerItemProxy; containerPortal = {ID("project")}; proxyType = 1; remoteGlobalIDString = {svcT}; remoteInfo = MacOnMacDiskBroker;')
proxy2=add('proxy-daemon',f'isa = PBXContainerItemProxy; containerPortal = {ID("project")}; proxyType = 1; remoteGlobalIDString = {dmnT}; remoteInfo = MacOnMacRawDiskDaemon;')
dep1=add('dependency-xpc',f'isa = PBXTargetDependency; target = {svcT}; targetProxy = {proxy1};')
dep2=add('dependency-daemon',f'isa = PBXTargetDependency; target = {dmnT}; targetProxy = {proxy2};')
# config helper

def conf(name,kind,debug):
 settings=['SWIFT_VERSION = 5.0','MACOSX_DEPLOYMENT_TARGET = 15.0','SDKROOT = macosx','CLANG_ENABLE_MODULES = YES','SWIFT_STRICT_CONCURRENCY = minimal','CODE_SIGN_STYLE = Automatic','ENABLE_HARDENED_RUNTIME = YES']
 if kind=='MacOnMac': settings += ['PRODUCT_BUNDLE_IDENTIFIER = ca.zensoftware.MacOnMac','PRODUCT_NAME = MacOnMac','INFOPLIST_FILE = Resources/Info.plist','GENERATE_INFOPLIST_FILE = NO','CODE_SIGN_ENTITLEMENTS = Resources/MacOnMac.entitlements']
 elif kind=='MacOnMacDiskBroker': settings += ['PRODUCT_BUNDLE_IDENTIFIER = ca.zensoftware.MacOnMac.DiskBroker','PRODUCT_NAME = MacOnMacDiskBroker','INFOPLIST_FILE = Helpers/VolumeBootDiskBroker/Info.plist','GENERATE_INFOPLIST_FILE = NO','CODE_SIGN_ENTITLEMENTS = ""']
 else: settings += ['PRODUCT_BUNDLE_IDENTIFIER = ca.zensoftware.MacOnMac.RawDiskBroker','PRODUCT_NAME = MacOnMacRawDiskDaemon','GENERATE_INFOPLIST_FILE = YES','CODE_SIGN_ENTITLEMENTS = ""']
 if debug: settings += ['SWIFT_OPTIMIZATION_LEVEL = "-Onone"','DEBUG_INFORMATION_FORMAT = dwarf']
 else:settings+=['SWIFT_OPTIMIZATION_LEVEL = "-O"','SWIFT_COMPILATION_MODE = wholemodule']
 return add(f'conf-{kind}-{name}','isa = XCBuildConfiguration; buildSettings = { '+ '; '.join(settings)+'; }; name = '+name+';')

def configlist(kind):
 a=conf('Debug',kind,True);b=conf('Release',kind,False)
 return add('cflist-'+kind,f'isa = XCConfigurationList; buildConfigurations = ( {a}, {b}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
for target in ['MacOnMac','MacOnMacDiskBroker','MacOnMacRawDiskDaemon']:
 confref=configlist(target)
 if target=='MacOnMac':
  phaseslist=[phases[target],frameworks[target],embed,post];prod=appProduct;ptype='com.apple.product-type.application';deps=[dep1,dep2]
 elif target=='MacOnMacDiskBroker':
  phaseslist=[phases[target],frameworks[target]];prod=svcProduct;ptype='com.apple.product-type.xpc-service';deps=[]
 else:
  phaseslist=[phases[target],frameworks[target]];prod=dmnProduct;ptype='com.apple.product-type.tool';deps=[]
 add('target-'+target,'isa = PBXNativeTarget; buildConfigurationList = '+confref+'; buildPhases = '+items(phaseslist)+'; buildRules = (); dependencies = '+items(deps)+'; name = '+target+'; productName = '+target+'; productReference = '+prod+'; productType = '+q(ptype)+';')
prjCfg1=add('projectDebug','isa = XCBuildConfiguration; buildSettings = { SWIFT_VERSION = 5.0; MACOSX_DEPLOYMENT_TARGET = 15.0; SDKROOT = macosx; }; name = Debug;')
prjCfg2=add('projectRelease','isa = XCBuildConfiguration; buildSettings = { SWIFT_VERSION = 5.0; MACOSX_DEPLOYMENT_TARGET = 15.0; SDKROOT = macosx; }; name = Release;')
prjConfig=add('prjconf',f'isa = XCConfigurationList; buildConfigurations = ( {prjCfg1}, {prjCfg2}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
proj=add('project','isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 1600; TargetAttributes = { '+appT+' = {CreatedOnToolsVersion = 16.0;}; '+svcT+' = {CreatedOnToolsVersion = 16.0;}; '+dmnT+' = {CreatedOnToolsVersion = 16.0;}; }; }; buildConfigurationList = '+prjConfig+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, ); mainGroup = '+rootGroup+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = ( '+appT+', '+svcT+', '+dmnT+', );')
content='// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'
for key,body in obj.items(): content+=f'  {key} = {{ {body} }};\n'
content+=' };\n rootObject = '+proj+';\n}\n'
out.write_text(content)
print(f'Wrote Xcode project: {len(obj)} objects, {len(app_sources)} app Swift files, {len(xpc_sources)} service Swift files, {len(daemon_sources)} daemon Swift files')
