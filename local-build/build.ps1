# Builds FileConverter.exe from this source tree with the .NET SDK - no Visual Studio needed.
#
# The legacy FileConverter.csproj needs Visual Studio's WPF build targets, so this script mirrors the sources into
# %TEMP%\FileConverter-local-build and generates an SDK-style project from the legacy item list. Third-party assemblies
# are compiled against the copies in the installed File Converter, so the new exe binds to exactly the DLLs that
# will sit next to it. NuGet restores only the .NET Framework 4.8 reference assemblies and NetOffice.
#
# Usage:  .\build.ps1                      (then .\deploy.ps1 to install the result)
param(
    [string]$InstallDir = "C:\Program Files\File Converter"
)
$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo "Application\FileConverter"
$mirror = Join-Path $env:TEMP "FileConverter-local-build\FileConverter"

if (-not (Test-Path -LiteralPath (Join-Path $InstallDir "FileConverter.exe"))) {
    throw "File Converter is not installed in '$InstallDir'. Install the official release first; this build compiles against its DLLs."
}

# 1. Mirror the sources (fresh every build so edits are picked up).
New-Item -ItemType Directory -Force -Path $mirror | Out-Null
robocopy $src $mirror /MIR /XD bin obj /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }

# 2. Generate the SDK-style project from the legacy item list.
$legacy = [xml](Get-Content -LiteralPath (Join-Path $src "FileConverter.csproj") -Raw)
$ns = New-Object Xml.XmlNamespaceManager($legacy.NameTable)
$ns.AddNamespace("m", "http://schemas.microsoft.com/developer/msbuild/2003")

$items = foreach ($itemType in @("ApplicationDefinition", "Compile", "Page", "EmbeddedResource", "Resource")) {
    $legacy.SelectNodes("//m:ItemGroup/m:$itemType", $ns) | ForEach-Object {
        "    <$itemType Include=`"$([Security.SecurityElement]::Escape($_.GetAttribute("Include")))`" />"
    }
}

# Framework references (WPF comes from UseWPF). PresentationUI is listed by the legacy project but unused.
$references = @("System.ComponentModel.Composition", "System.ComponentModel.DataAnnotations", "System.Drawing", "System.Numerics",
    "System.Windows.Forms", "System.Xml", "Microsoft.CSharp", "System.Core", "UIAutomationProvider", "UIAutomationTypes") |
    ForEach-Object { "    <Reference Include=`"$_`" />" }

# Third-party assemblies: Middleware copies for the ones the installer takes from there, the installed copies for the rest.
$hintPaths = [ordered]@{
    "Markdown.Xaml" = Join-Path $repo "Middleware\Markdown.Xaml.dll"
    "Ripper" = Join-Path $repo "Middleware\Ripper.dll"
    "yeti.mmedia" = Join-Path $repo "Middleware\yeti.mmedia.dll"
}
foreach ($name in @("FileConverterExtension", "CommunityToolkit.Mvvm", "Magick.NET-Q16-AnyCPU", "Magick.NET.Core", "Microsoft.Extensions.DependencyInjection",
        "Microsoft.Extensions.DependencyInjection.Abstractions", "Microsoft.Bcl.AsyncInterfaces", "Microsoft.Xaml.Behaviors", "SharpShell", "WpfAnimatedGif",
        "System.Buffers", "System.Memory", "System.Numerics.Vectors", "System.Runtime.CompilerServices.Unsafe", "System.Threading.Tasks.Extensions",
        "System.ComponentModel.Annotations")) {
    $hintPaths[$name] = Join-Path $InstallDir "$name.dll"
}
foreach ($entry in $hintPaths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) { throw "Missing reference: $($entry.Value)" }
    $references += "    <Reference Include=`"$($entry.Key)`"><HintPath>$($entry.Value)</HintPath><Private>false</Private></Reference>"
}

$project = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net48</TargetFramework>
    <UseWPF>true</UseWPF>
    <AssemblyName>FileConverter</AssemblyName>
    <RootNamespace>FileConverter</RootNamespace>
    <!-- Visual Studio compiles legacy .NET Framework projects as C# 7.3: stay compatible with the upstream build. -->
    <LangVersion>7.3</LangVersion>
    <EnableDefaultItems>false</EnableDefaultItems>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
    <ApplicationIcon>Resources\ApplicationIcon.ico</ApplicationIcon>
    <PlatformTarget>x64</PlatformTarget>
    <Prefer32Bit>false</Prefer32Bit>
    <Optimize>true</Optimize>
    <DebugType>pdbonly</DebugType>
    <NoWarn>`$(NoWarn);CS0162;CS0618;CS1591</NoWarn>
  </PropertyGroup>
  <ItemGroup>
$($items -join "`n")
  </ItemGroup>
  <ItemGroup>
$($references -join "`n")
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NETFramework.ReferenceAssemblies" Version="1.0.3" PrivateAssets="all" />
    <PackageReference Include="NetOffice.Excel" Version="1.7.4.11" />
    <PackageReference Include="NetOffice.PowerPoint" Version="1.7.4.11" />
    <PackageReference Include="NetOffice.Word" Version="1.7.4.11" />
  </ItemGroup>
</Project>
"@
$projectPath = Join-Path $mirror "FileConverter.LocalBuild.csproj"
[IO.File]::WriteAllText($projectPath, $project, (New-Object System.Text.UTF8Encoding($false)))

# 3. Build.
dotnet build $projectPath -c Release -nologo -v:minimal "-clp:NoSummary"
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }

$output = Join-Path $mirror "bin\Release\net48"
Write-Host "Built $(Join-Path $output 'FileConverter.exe')"
Write-Host "Next: .\deploy.ps1"
