{
  This file is part of PasBuild.

  Copyright (c) 2025 Graeme Geldenhuys <graemeg@gmail.com>

  SPDX-License-Identifier: BSD-3-Clause

  See LICENSE file in the project root for full license terms.
}

unit PasBuild.Command.AggregatedPackage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Zipper,
  PasBuild.Types,
  PasBuild.Command,
  PasBuild.Command.Reactor,
  PasBuild.Utils;

type
  { Aggregated package command - creates single release archive for multi-module projects }
  TAggregatedPackageCommand = class(TBuildCommand)
  private
    FRegistry: TModuleRegistry;
    FSelectedModule: string;
    function GetArchiveFileName: string;
    function FindFileWithVariants(const ABaseName: string): string;
    function CollectApplicationExecutables: TStringList;
    function CreateAggregatedArchive(const AArchiveName: string): Integer;
  protected
    function GetName: string; override;
  public
    constructor Create(AConfig: TProjectConfig; AProfileIds: TStringList;
      ARegistry: TModuleRegistry; const ASelectedModule: string = ''); reintroduce;
    function Execute: Integer; override;
    function GetDependencies: TBuildCommandList; override;
  end;

implementation

{ TAggregatedPackageCommand }

constructor TAggregatedPackageCommand.Create(AConfig: TProjectConfig; AProfileIds: TStringList;
  ARegistry: TModuleRegistry; const ASelectedModule: string = '');
begin
  inherited Create(AConfig, AProfileIds);
  FRegistry := ARegistry;
  FSelectedModule := ASelectedModule;
end;

function TAggregatedPackageCommand.GetName: string;
begin
  Result := 'aggregated-package';
end;

function TAggregatedPackageCommand.GetDependencies: TBuildCommandList;
begin
  Result := TBuildCommandList.Create(False); // Don't own the objects
  try
    // Aggregated package depends on: reactor compile (builds all modules, or selected module)
    Result.Add(TReactorCommand.Create(Config, ProfileIds, FRegistry, 'compile', FSelectedModule));
  except
    Result.Free;
    raise;
  end;
end;

function TAggregatedPackageCommand.GetArchiveFileName: string;
var
  BaseName, OutputDir, Version: string;
  I: Integer;
  Module: TModuleInfo;
begin
  if FSelectedModule <> '' then
  begin
    // Single-module package: archive goes into the module's own target/ directory
    for I := 0 to FRegistry.Modules.Count - 1 do
    begin
      Module := TModuleInfo(FRegistry.Modules[I]);
      if CompareText(Module.Name, FSelectedModule) = 0 then
      begin
        OutputDir := Module.Path + DirectorySeparator + 'target';
        Version := Module.Config.Version;
        if Version = '' then
          Version := Config.Version;
        Result := OutputDir + DirectorySeparator + Module.Name + '-' + Version + '.zip';
        Exit;
      end;
    end;
  end;

  // Full aggregated package: archive goes into the aggregator's target/ directory
  OutputDir := TUtils.NormalizePath(Config.BuildConfig.OutputDirectory);
  BaseName := Config.Name;
  if BaseName = '' then
    BaseName := 'project';
  Result := OutputDir + DirectorySeparator + BaseName + '-' + Config.Version + '.zip';
end;

function TAggregatedPackageCommand.FindFileWithVariants(const ABaseName: string): string;
const
  FileExtensions: array[0..4] of string = (
    '',           // No extension
    '.txt',
    '.md',
    '.adoc',
    '.rst'
  );
var
  Extension, FileName: string;
begin
  Result := '';

  for Extension in FileExtensions do
  begin
    FileName := ABaseName + Extension;
    if FileExists(FileName) then
    begin
      Result := FileName;
      Exit;
    end;
  end;
end;

function TAggregatedPackageCommand.CollectApplicationExecutables: TStringList;
var
  I: Integer;
  Module: TModuleInfo;
  ExeName, ExePath: string;
begin
  Result := TStringList.Create;

  // Collect executables from application modules only
  for I := 0 to FRegistry.Modules.Count - 1 do
  begin
    Module := TModuleInfo(FRegistry.Modules[I]);

    // Honour -m / --module selection
    if (FSelectedModule <> '') and (CompareText(Module.Name, FSelectedModule) <> 0) then
      Continue;

    // Skip aggregators and libraries - only include applications
    if Module.Config.BuildConfig.ProjectType <> ptApplication then
      Continue;

    // Get executable name with platform suffix
    ExeName := Module.Config.BuildConfig.ExecutableName;
    if ExeName = '' then
      ExeName := 'app';

    ExeName := ExeName + TUtils.GetPlatformExecutableSuffix;

    // Build full path to executable
    ExePath := Module.Path + DirectorySeparator + 'target' + DirectorySeparator + ExeName;

    if FileExists(ExePath) then
    begin
      Result.Add(ExePath);
      TUtils.LogInfo('Found application executable: ' + ExePath);
    end
    else
      TUtils.LogWarning('Expected executable not found: ' + ExePath);
  end;
end;

function TAggregatedPackageCommand.CreateAggregatedArchive(const AArchiveName: string): Integer;
var
  Zip: TZipper;
  FilesToAdd: TStringList;
  FileToAdd, LicenseFile, ReadmeFile: string;
begin
  Result := 0;

  // Collect all application executables
  FilesToAdd := CollectApplicationExecutables;
  try
    // Check if we found any executables
    if FilesToAdd.Count = 0 then
    begin
      TUtils.LogError('No application modules found to package');
      TUtils.LogError('Multi-module package requires at least one module with packaging=application');
      Result := 1;
      Exit;
    end;

    // Include aggregator's LICENSE file (with variants)
    LicenseFile := FindFileWithVariants('LICENSE');
    if LicenseFile = '' then
      LicenseFile := FindFileWithVariants('COPYING');

    if LicenseFile <> '' then
      FilesToAdd.Add(LicenseFile)
    else
      TUtils.LogInfo('LICENSE/COPYING file not found in aggregator, skipping');

    // Include aggregator's README file
    ReadmeFile := FindFileWithVariants('README');
    if ReadmeFile <> '' then
      FilesToAdd.Add(ReadmeFile)
    else
      TUtils.LogInfo('README file not found in aggregator, skipping');

    // Create the ZIP archive
    Zip := TZipper.Create;
    try
      Zip.FileName := AArchiveName;

      // Add files with flat structure (no directories)
      for FileToAdd in FilesToAdd do
      begin
        if FileExists(FileToAdd) then
        begin
          TUtils.LogInfo('Adding to archive: ' + FileToAdd);
          Zip.Entries.AddFileEntry(FileToAdd, ExtractFileName(FileToAdd));
        end;
      end;

      // Create the archive
      if Zip.Entries.Count > 0 then
      begin
        Zip.ZipAllFiles;
        TUtils.LogInfo('Created aggregated archive: ' + AArchiveName);
      end
      else
      begin
        TUtils.LogError('No files to include in aggregated package');
        Result := 1;
      end;

    finally
      Zip.Free;
    end;

  finally
    FilesToAdd.Free;
  end;
end;

function TAggregatedPackageCommand.Execute: Integer;
var
  ArchiveName, OutputDir: string;
begin
  Result := 0;

  if FSelectedModule <> '' then
    TUtils.LogInfo('Creating release package for module: ' + FSelectedModule)
  else
    TUtils.LogInfo('Creating aggregated release package for multi-module project...');

  // Derive archive name first; output directory follows from it
  ArchiveName := GetArchiveFileName;
  OutputDir := ExtractFilePath(ArchiveName);
  if not ForceDirectories(OutputDir) then
  begin
    TUtils.LogError('Failed to create output directory: ' + OutputDir);
    Result := 1;
    Exit;
  end;

  // Delete existing archive if present
  if FileExists(ArchiveName) then
  begin
    TUtils.LogInfo('Removing existing archive: ' + ArchiveName);
    if not DeleteFile(ArchiveName) then
    begin
      TUtils.LogError('Failed to delete existing archive: ' + ArchiveName);
      Result := 1;
      Exit;
    end;
  end;

  // Create the aggregated archive
  Result := CreateAggregatedArchive(ArchiveName);

  if Result = 0 then
    TUtils.LogInfo('Aggregated package created successfully: ' + ArchiveName)
  else
    TUtils.LogError('Aggregated package creation failed');
end;

end.
