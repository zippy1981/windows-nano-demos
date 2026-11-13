program hello;

begin
  WriteLn('Hello from Free Pascal ', {$I %FPCVERSION%}, ' on ', {$I %FPCTARGETOS%}, '/', {$I %FPCTARGETCPU%});
end.
