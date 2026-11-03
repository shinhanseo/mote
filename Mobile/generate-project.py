"""Dependency-free, deterministic Xcode project generation. Run from anywhere."""
from pathlib import Path
import hashlib,plistlib
root=Path(__file__).resolve().parent
objects={}
def ident(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name,body):objects[ident(name)]=body;return ident(name)
files=['MoteMobile/MoteMobileApp.swift','MoteMobile/MobileStore.swift','MoteMobile/DustView.swift','../Sources/CloudRelay.swift']
refs=[];builds=[]
for name in files:
 ref=add(name,f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }}');refs.append(ref)
 builds.append(add('build '+name,f'{{isa = PBXBuildFile; fileRef = {ref}; }}'))
assets=add('assets','{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = MoteMobile/Assets.xcassets; sourceTree = "<group>";}');refs.append(assets)
resource=add('build assets',f'{{isa = PBXBuildFile; fileRef = {assets};}}')
localizations=[]
for language in ['ko','en']:
 ref=add('strings '+language,f'{{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {language}; path = "MoteMobile/{language}.lproj/Localizable.strings"; sourceTree = "<group>";}}');localizations.append(ref)
strings=add('strings',f'{{isa = PBXVariantGroup; children = ({",".join(localizations)},); name = Localizable.strings; sourceTree = "<group>";}}');refs.append(strings)
strbuild=add('build strings',f'{{isa = PBXBuildFile; fileRef = {strings};}}')
product=add('product','{isa = PBXFileReference; explicitFileType = wrapper.application; path = MoteMobile.app; sourceTree = BUILT_PRODUCTS_DIR;}')
products=add('products',f'{{isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";}}')
group=add('main group',f'{{isa = PBXGroup; children = ({",".join(refs)},{products},); sourceTree = "<group>";}}')
sources=add('sources',f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;}}')
resources=add('resources',f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({resource},{strbuild},); runOnlyForDeploymentPostprocessing = 0;}}')
frameworks=add('frameworks','{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
pcs=[];tcs=[]
for config in ['Debug','CloudDebug','Release']:
 debug=config!='Release';cloud=config!='Debug'
 pcs.append(add('project '+config,f'{{isa = XCBuildConfiguration; name = {config}; buildSettings = {{SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "'+('-Onone' if debug else '-O')+'"; DEBUG_INFORMATION_FORMAT = dwarf;};}'))
 settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'im.mote.companion.mobile','DEVELOPMENT_TEAM':'2RQKCF6Z9C','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'MoteMobile/InfoCloud.plist' if cloud else 'MoteMobile/Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'4','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SWIFT_EMIT_LOC_STRINGS':'YES','ENABLE_PREVIEWS':'YES','SUPPORTS_MACCATALYST':'NO','MOTE_CLOUD_ENVIRONMENT':'Production' if config=='Release' else 'Development'}
 if cloud:settings['CODE_SIGN_ENTITLEMENTS']='MoteMobile/MoteMobile.entitlements'
 tcs.append(add('target '+config,'{isa = XCBuildConfiguration; name = '+config+'; buildSettings = {'+''.join(f'{k} = "{v}";' for k,v in settings.items())+'};}'))
pc=add('project configs',f'{{isa = XCConfigurationList; buildConfigurations = ({",".join(pcs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
tc=add('target configs',f'{{isa = XCConfigurationList; buildConfigurations = ({",".join(tcs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
target=add('target',f'{{isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = MoteMobile; productName = MoteMobile; productReference = {product}; productType = "com.apple.product-type.application";}}')
project=add('project',f'{{isa = PBXProject; attributes = {{LastUpgradeCheck = 1600; TargetAttributes = {{{target} = {{CreatedOnToolsVersion = 16.0; DevelopmentTeam = 2RQKCF6Z9C; SystemCapabilities = {{com.apple.iCloud = {{enabled = 1;}};com.apple.Push = {{enabled = 1;}};}};}};}};}}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ko; hasScannedForEncodings = 0; knownRegions = (ko,en,Base,); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);}}')
(root/'MoteMobile.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(k+' = '+v+';\n' for k,v in objects.items())+'}; rootObject = '+project+';}\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="MoteMobile.app" BlueprintName="MoteMobile" ReferencedContainer="container:MoteMobile.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="MoteMobile.app" BlueprintName="MoteMobile" ReferencedContainer="container:MoteMobile.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(root/'MoteMobile.xcodeproj/xcshareddata/xcschemes/MoteMobile.xcscheme').write_text(scheme)
base={'CFBundleDisplayName':'Mote','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UIBackgroundModes':['remote-notification'],'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'MoteCloudKitEnabled':False,'ITSAppUsesNonExemptEncryption':False}
for name,cloud in [('Info.plist',False),('InfoCloud.plist',True)]:
 base['MoteCloudKitEnabled']=cloud;(root/'MoteMobile'/name).write_bytes(plistlib.dumps(base))
(root/'MoteMobile/MoteMobile.entitlements').write_bytes(plistlib.dumps({'aps-environment':'development','com.apple.developer.icloud-container-environment':'$(MOTE_CLOUD_ENVIRONMENT)','com.apple.developer.icloud-services':['CloudKit'],'com.apple.developer.icloud-container-identifiers':['iCloud.im.mote.companion']}))
