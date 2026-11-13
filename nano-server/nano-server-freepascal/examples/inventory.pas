program inventory;

{ Uses the object model, generics, exceptions and three packages (rtl-objpas, fcl-base and fcl-json),
  so compiling it shows that the unit search path in fpc.cfg reaches every package. }

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Generics.Collections, fpjson;

type
  TStock = specialize TDictionary<string, Integer>;

var
  Stock: TStock;
  Names: TStringList;
  Report: TJSONObject;
  Name: string;
  Total: Integer;
begin
  Stock := TStock.Create;
  Names := TStringList.Create;
  Report := TJSONObject.Create;
  try
    Stock.Add('widgets', 12);
    Stock.Add('gears', 30);
    for Name in Stock.Keys do
      Names.Add(Name);
    Names.Sort;
    Total := 0;
    for Name in Names do
    begin
      Report.Add(Name, Stock[Name]);
      Total := Total + Stock[Name];
    end;
    Report.Add('total', Total);
    try
      Stock.Add('gears', 1);
    except
      on E: Exception do
        Report.Add('duplicate', E.ClassName);
    end;
    WriteLn(Report.AsJSON);
  finally
    Report.Free;
    Names.Free;
    Stock.Free;
  end;
end.
