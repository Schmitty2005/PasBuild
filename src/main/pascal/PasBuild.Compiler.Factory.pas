{
  This file is part of PasBuild.

  Copyright (c) 2025-2026 Graeme Geldenhuys <graemeg@gmail.com>

  SPDX-License-Identifier: BSD-3-Clause

  See LICENSE file in the project root for full license terms.
}

unit PasBuild.Compiler.Factory;

{$mode objfpc}{$H+}

interface

uses
  PasBuild.Compiler.Backend;

type
  { Creates the appropriate TCompilerBackend for a given executable.

    Detection strategy: run '<exe> --help' and look for "Blaise" in the
    first line of output.  Blaise prints "Blaise Compiler vX.Y.Z" there;
    FPC does not respond to --help with that string.  Falls back to FPC
    when detection is inconclusive. }
  TCompilerBackendFactory = class
  public
    class function CreateFromExecutable(const AExecutable: string): TCompilerBackend;
  end;

implementation

uses
  SysUtils,
  PasBuild.Utils,
  PasBuild.Compiler.FPC,
  PasBuild.Compiler.Blaise;

class function TCompilerBackendFactory.CreateFromExecutable(
  const AExecutable: string): TCompilerBackend;
var
  Output: string;
  FirstLine: string;
  P: Integer;
begin
  TUtils.ExecuteProcessWithCapture(AExecutable + ' --help', Output);
  FirstLine := Output;
  P := Pos(LineEnding, FirstLine);
  if P > 0 then
    FirstLine := Copy(FirstLine, 1, P - 1);

  if Pos('Blaise', FirstLine) > 0 then
    Result := TBlaiseBackend.Create(AExecutable)
  else
    Result := TFPCBackend.Create(AExecutable);
end;

end.
