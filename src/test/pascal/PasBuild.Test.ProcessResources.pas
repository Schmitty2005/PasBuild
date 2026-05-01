{
  This file is part of PasBuild.

  Copyright (c) 2025-2026 Graeme Geldenhuys <graemeg@gmail.com>

  SPDX-License-Identifier: BSD-3-Clause

  See LICENSE file in the project root for full license terms.
}

unit PasBuild.Test.ProcessResources;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  { Test variable filtering in process-resources }
  TTestProcessResourcesFiltering = class(TTestCase)
  private
    FTempSrcDir: string;
    FTempTargetDir: string;
    function RunFiltering(const AContent: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { project.* tokens }
    procedure TestProjectNameToken;
    procedure TestProjectVersionToken;
    { build.* tokens }
    procedure TestBuildDateTokenReplaced;
    procedure TestBuildDateTokenISO8601Format;
    procedure TestBuildTimeTokenReplaced;
    procedure TestBuildTimeTokenHHNNSSFormat;
    procedure TestBuildTimestampTokenReplaced;
    procedure TestBuildTimestampTokenISO8601Format;
    procedure TestBuildTimestampContainsDateAndTime;
    procedure TestMultipleBuildTokensInOneFile;
    procedure TestUnknownTokenLeftUnchanged;
  end;

implementation

uses
  PasBuild.Types,
  PasBuild.Command.ProcessResources;

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

{ TTestProcessResourcesFiltering }

procedure TTestProcessResourcesFiltering.SetUp;
begin
  FTempSrcDir := GetTempDir + 'pasbuild_test_src_' + IntToStr(GetProcessID) + PathDelim;
  FTempTargetDir := GetTempDir + 'pasbuild_test_tgt_' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(FTempSrcDir);
  ForceDirectories(FTempTargetDir);
end;

procedure TTestProcessResourcesFiltering.TearDown;
begin
  if DirectoryExists(FTempSrcDir) then
    DeleteDirRecursive(FTempSrcDir);
  if DirectoryExists(FTempTargetDir) then
    DeleteDirRecursive(FTempTargetDir);
end;

function TTestProcessResourcesFiltering.RunFiltering(const AContent: string): string;
var
  Config: TProjectConfig;
  ResConfig: TResourcesConfig;
  Cmd: TProcessResourcesCommand;
  InputFile, OutputFile: string;
  F: TextFile;
  Line, FileContent: string;
begin
  InputFile := FTempSrcDir + 'test.txt';
  OutputFile := FTempTargetDir + 'test.txt';

  AssignFile(F, InputFile);
  Rewrite(F);
  Write(F, AContent);
  CloseFile(F);

  Config := TProjectConfig.Create;
  try
    Config.Name := 'TestProject';
    Config.Version := '1.2.3';
    Config.Author := 'Test Author';
    Config.License := 'MIT';
    Config.ResourcesConfig.Directory := ExcludeTrailingPathDelimiter(FTempSrcDir);
    Config.ResourcesConfig.Filtering := True;
    Config.BuildConfig.OutputDirectory := ExcludeTrailingPathDelimiter(FTempTargetDir);

    Cmd := TProcessResourcesCommand.Create(Config, Config.ResourcesConfig, FTempTargetDir);
    try
      Cmd.Execute;
    finally
      Cmd.Free;
    end;
  finally
    Config.Free;
  end;

  FileContent := '';
  if FileExists(OutputFile) then
  begin
    AssignFile(F, OutputFile);
    Reset(F);
    try
      while not EOF(F) do
      begin
        ReadLn(F, Line);
        FileContent := FileContent + Line;
      end;
    finally
      CloseFile(F);
    end;
  end;
  Result := FileContent;
end;

{ project.* token tests }

procedure TTestProcessResourcesFiltering.TestProjectNameToken;
begin
  AssertEquals('${project.name} should be replaced with project name',
    'TestProject', RunFiltering('${project.name}'));
end;

procedure TTestProcessResourcesFiltering.TestProjectVersionToken;
begin
  AssertEquals('${project.version} should be replaced with project version',
    '1.2.3', RunFiltering('${project.version}'));
end;

{ build.* token tests }

procedure TTestProcessResourcesFiltering.TestBuildDateTokenReplaced;
var
  Result: string;
begin
  Result := RunFiltering('${build.date}');
  AssertTrue('${build.date} should not remain as the literal token',
    Result <> '${build.date}');
  AssertTrue('${build.date} result should not be empty', Result <> '');
end;

procedure TTestProcessResourcesFiltering.TestBuildDateTokenISO8601Format;
var
  DateStr: string;
begin
  DateStr := RunFiltering('${build.date}');
  AssertEquals('Date should be 10 characters (yyyy-mm-dd)', 10, Length(DateStr));
  AssertEquals('Year-month separator should be hyphen', '-', DateStr[5]);
  AssertEquals('Month-day separator should be hyphen', '-', DateStr[8]);
end;

procedure TTestProcessResourcesFiltering.TestBuildTimeTokenReplaced;
var
  Result: string;
begin
  Result := RunFiltering('${build.time}');
  AssertTrue('${build.time} should not remain as the literal token',
    Result <> '${build.time}');
  AssertTrue('${build.time} result should not be empty', Result <> '');
end;

procedure TTestProcessResourcesFiltering.TestBuildTimeTokenHHNNSSFormat;
var
  TimeStr: string;
begin
  TimeStr := RunFiltering('${build.time}');
  AssertEquals('Time should be 8 characters (hh:nn:ss)', 8, Length(TimeStr));
  AssertEquals('Hour-minute separator should be colon', ':', TimeStr[3]);
  AssertEquals('Minute-second separator should be colon', ':', TimeStr[6]);
end;

procedure TTestProcessResourcesFiltering.TestBuildTimestampTokenReplaced;
var
  Result: string;
begin
  Result := RunFiltering('${build.timestamp}');
  AssertTrue('${build.timestamp} should not remain as the literal token',
    Result <> '${build.timestamp}');
  AssertTrue('${build.timestamp} result should not be empty', Result <> '');
end;

procedure TTestProcessResourcesFiltering.TestBuildTimestampTokenISO8601Format;
var
  TsStr: string;
begin
  TsStr := RunFiltering('${build.timestamp}');
  AssertEquals('Timestamp should be 19 characters (yyyy-mm-ddThh:nn:ss)', 19, Length(TsStr));
  AssertEquals('Date-time separator should be T', 'T', TsStr[11]);
end;

procedure TTestProcessResourcesFiltering.TestBuildTimestampContainsDateAndTime;
var
  TsStr, DateStr, TimeStr: string;
begin
  TsStr  := RunFiltering('${build.timestamp}');
  DateStr := RunFiltering('${build.date}');
  TimeStr := RunFiltering('${build.time}');
  AssertEquals('Timestamp date part should match ${build.date}',
    DateStr, Copy(TsStr, 1, 10));
  AssertEquals('Timestamp time part should match ${build.time}',
    TimeStr, Copy(TsStr, 12, 8));
end;

procedure TTestProcessResourcesFiltering.TestMultipleBuildTokensInOneFile;
var
  Output: string;
begin
  Output := RunFiltering('date=${build.date} time=${build.time}');
  AssertTrue('Both tokens should be replaced — no literal ${build.date}',
    Pos('${build.date}', Output) = 0);
  AssertTrue('Both tokens should be replaced — no literal ${build.time}',
    Pos('${build.time}', Output) = 0);
end;

procedure TTestProcessResourcesFiltering.TestUnknownTokenLeftUnchanged;
begin
  AssertEquals('Unknown token should be left as-is',
    '${unknown.token}', RunFiltering('${unknown.token}'));
end;

initialization
  RegisterTest(TTestProcessResourcesFiltering);

end.
