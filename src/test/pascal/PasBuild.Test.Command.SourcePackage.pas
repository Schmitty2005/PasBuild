{
  This file is part of PasBuild.

  Copyright (c) 2025-2026 Graeme Geldenhuys <graemeg@gmail.com>

  SPDX-License-Identifier: BSD-3-Clause

  See LICENSE file in the project root for full license terms.
}

unit PasBuild.Test.Command.SourcePackage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  { Tests for the aggregated source-package command, focusing on how a
    module's configured <sourceDirectory> is honoured when collecting
    sources into the archive. }
  TTestAggregatedSourcePackage = class(TTestCase)
  private
    FTempRoot: string;          // aggregator project root
    FPrevDir: string;           // CWD to restore in TearDown
    procedure WriteTextFile(const APath, AContent: string);
    function ArchiveEntries(const AArchiveName: string): TStringList;
    function RunForModule(const ASelectedModule: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Module root layout: <sourceDirectory>.</sourceDirectory> }
    procedure TestFlatRootModuleIncludesSources;
    procedure TestFlatRootModuleSourceIsFlatUnderModuleDir;
    procedure TestFlatRootModuleExcludesTargetDir;
    { Standard layout: <sourceDirectory>src/main/pascal</sourceDirectory> }
    procedure TestStandardLayoutModuleIncludesSources;
    procedure TestStandardLayoutPreservesSourceDirectory;
  end;

implementation

uses
  Zipper,
  PasBuild.Types,
  PasBuild.Command.AggregatedSourcePackage;

procedure DeleteDirRecursive(const ADir: string);
var
  SR: TSearchRec;
  Path: string;
begin
  Path := IncludeTrailingPathDelimiter(ADir);
  if FindFirst(Path + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then
          Continue;
        if (SR.Attr and faDirectory) <> 0 then
          DeleteDirRecursive(Path + SR.Name)
        else
          DeleteFile(Path + SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
  RemoveDir(ADir);
end;

{ TTestAggregatedSourcePackage }

procedure TTestAggregatedSourcePackage.WriteTextFile(const APath, AContent: string);
var
  F: TextFile;
begin
  ForceDirectories(ExtractFileDir(APath));
  AssignFile(F, APath);
  Rewrite(F);
  try
    Write(F, AContent);
  finally
    CloseFile(F);
  end;
end;

procedure TTestAggregatedSourcePackage.SetUp;
var
  S: string;
begin
  FPrevDir := GetCurrentDir;
  FTempRoot := IncludeTrailingPathDelimiter(GetTempDir)
    + 'pasbuild_test_srcpkg_' + IntToStr(GetProcessID);
  ForceDirectories(FTempRoot);

  // Aggregator project.xml (read relative to CWD by the command)
  WriteTextFile(FTempRoot + PathDelim + 'project.xml',
    '<project>' + LineEnding +
    '  <name>agg</name>' + LineEnding +
    '  <version>9.9.0</version>' + LineEnding +
    '  <packaging>pom</packaging>' + LineEnding +
    '</project>');

  // Module A: sources directly in the module root (<sourceDirectory>.)
  S := FTempRoot + PathDelim + 'mod-flat';
  WriteTextFile(S + PathDelim + 'project.xml', '<project><name>mod-flat</name></project>');
  WriteTextFile(S + PathDelim + 'main.pas', 'unit main; // flat-root source');
  WriteTextFile(S + PathDelim + 'helper.pas', 'unit helper;');
  // Build output that must NOT be bundled
  WriteTextFile(S + PathDelim + 'target' + PathDelim + 'stale-src.zip', 'GARBAGE');

  // Module B: standard layout src/main/pascal
  S := FTempRoot + PathDelim + 'mod-std';
  WriteTextFile(S + PathDelim + 'project.xml', '<project><name>mod-std</name></project>');
  WriteTextFile(S + PathDelim + 'src' + PathDelim + 'main' + PathDelim + 'pascal'
    + PathDelim + 'Foo.pas', 'unit Foo;');

  SetCurrentDir(FTempRoot);
end;

procedure TTestAggregatedSourcePackage.TearDown;
begin
  SetCurrentDir(FPrevDir);
  if DirectoryExists(FTempRoot) then
    DeleteDirRecursive(FTempRoot);
end;

function TTestAggregatedSourcePackage.ArchiveEntries(const AArchiveName: string): TStringList;
var
  Unzip: TUnZipper;
  I: Integer;
  EntryName: string;
begin
  Result := TStringList.Create;
  Unzip := TUnZipper.Create;
  try
    Unzip.FileName := AArchiveName;
    Unzip.Examine;
    for I := 0 to Unzip.Entries.Count - 1 do
    begin
      // Normalise to forward slashes so assertions are platform-independent
      EntryName := StringReplace(Unzip.Entries[I].ArchiveFileName,
        '\', '/', [rfReplaceAll]);
      Result.Add(EntryName);
    end;
  finally
    Unzip.Free;
  end;
end;

{ Builds a registry mirroring the temp project tree, runs the command for the
  selected module, and returns the generated archive path. }
function TTestAggregatedSourcePackage.RunForModule(const ASelectedModule: string): string;
var
  AggConfig: TProjectConfig;
  Registry: TModuleRegistry;
  Profiles: TStringList;
  Cmd: TAggregatedSourcePackageCommand;

  function MakeModule(const AName, ARelPath, ASourceDir: string): TModuleInfo;
  begin
    Result := TModuleInfo.Create;
    Result.Name := AName;
    Result.Path := FTempRoot + PathDelim + ARelPath;
    Result.Config := TProjectConfig.Create;
    Result.Config.Name := AName;
    Result.Config.Version := '9.9.0';
    Result.Config.BuildConfig.SourceDirectory := ASourceDir;
  end;

begin
  AggConfig := TProjectConfig.Create;
  Registry := TModuleRegistry.Create;
  Profiles := TStringList.Create;
  try
    AggConfig.Name := 'agg';
    AggConfig.Version := '9.9.0';
    AggConfig.BuildConfig.OutputDirectory := FTempRoot + PathDelim + 'target';

    Registry.RegisterModule(MakeModule('mod-flat', 'mod-flat', '.'));
    Registry.RegisterModule(MakeModule('mod-std', 'mod-std', 'src/main/pascal'));

    Cmd := TAggregatedSourcePackageCommand.Create(AggConfig, Profiles, Registry,
      ASelectedModule);
    try
      AssertEquals('Command should succeed', 0, Cmd.Execute);
    finally
      Cmd.Free;
    end;

    // Archive for a single selected module lands in that module's target/
    Result := FTempRoot + PathDelim + ASelectedModule + PathDelim + 'target'
      + PathDelim + ASelectedModule + '-9.9.0-src.zip';
  finally
    Profiles.Free;
    Registry.Free;
    AggConfig.Free;
  end;
end;

procedure TTestAggregatedSourcePackage.TestFlatRootModuleIncludesSources;
var
  Archive: string;
  Entries: TStringList;
begin
  Archive := RunForModule('mod-flat');
  Entries := ArchiveEntries(Archive);
  try
    AssertTrue('Flat-root module main.pas must be in the archive',
      Entries.IndexOf('agg-9.9.0/mod-flat/main.pas') >= 0);
    AssertTrue('Flat-root module helper.pas must be in the archive',
      Entries.IndexOf('agg-9.9.0/mod-flat/helper.pas') >= 0);
  finally
    Entries.Free;
  end;
end;

procedure TTestAggregatedSourcePackage.TestFlatRootModuleSourceIsFlatUnderModuleDir;
var
  Archive: string;
  Entries: TStringList;
begin
  Archive := RunForModule('mod-flat');
  Entries := ArchiveEntries(Archive);
  try
    // For <sourceDirectory>. the sources are flat under <module>/, with no
    // spurious src/ segment.
    AssertTrue('No src/ segment should be introduced for flat-root layout',
      Entries.IndexOf('agg-9.9.0/mod-flat/src/main.pas') < 0);
  finally
    Entries.Free;
  end;
end;

procedure TTestAggregatedSourcePackage.TestFlatRootModuleExcludesTargetDir;
var
  Archive: string;
  Entries: TStringList;
  I: Integer;
begin
  Archive := RunForModule('mod-flat');
  Entries := ArchiveEntries(Archive);
  try
    for I := 0 to Entries.Count - 1 do
      AssertTrue('Build output under target/ must not be bundled: ' + Entries[I],
        Pos('/target/', '/' + Entries[I]) = 0);
  finally
    Entries.Free;
  end;
end;

procedure TTestAggregatedSourcePackage.TestStandardLayoutModuleIncludesSources;
var
  Archive: string;
  Entries: TStringList;
begin
  Archive := RunForModule('mod-std');
  Entries := ArchiveEntries(Archive);
  try
    AssertTrue('Standard-layout module source must be in the archive',
      Entries.IndexOf('agg-9.9.0/mod-std/src/main/pascal/Foo.pas') >= 0);
  finally
    Entries.Free;
  end;
end;

procedure TTestAggregatedSourcePackage.TestStandardLayoutPreservesSourceDirectory;
var
  Archive: string;
  Entries: TStringList;
begin
  Archive := RunForModule('mod-std');
  Entries := ArchiveEntries(Archive);
  try
    // The configured src/main/pascal layout must be preserved verbatim, not
    // flattened to <module>/Foo.pas.
    AssertTrue('Source must not be flattened away from src/main/pascal',
      Entries.IndexOf('agg-9.9.0/mod-std/Foo.pas') < 0);
  finally
    Entries.Free;
  end;
end;

initialization
  RegisterTest(TTestAggregatedSourcePackage);

end.
