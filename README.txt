FSDIAG.R4X
===========

FSDIAG prueft den aktuellen R4SYS-Dateisystemvertrag:

- Datei lesen, schreiben, anhaengen, kopieren, verschieben und loeschen
- Verzeichnisse und Laufwerksinformationen
- positionierte und gestreamte I/O-Pfade
- Offset-, Groessen-, Abschluss- und Abbruchregeln
- Cache-, Writeback- und Fehlerdiagnose

Der Test verwendet die aktuellen R4SYS-Felder und faellt nicht auf einen
zweiten Datei-I/O-Pfad zurueck.

Repository-Build
----------------

`build.zig` baut FSDIAG.R4X als eigenstaendiges SDK-Projekt. `Settings.R4S`
mappt SDK, Contract, Librarybindings, DevKit und die Artefaktausgabe. Relative
Werte beginnen am Repository-Root und duerfen durch absolute Pfade ersetzt
werden.

Unter Windows:

    Build.bat

Ergebnis:

    D:\R4OS\Artifacts\Modules\FsDiag\FSDIAG.R4X

Der Build konsumiert nur die gepinnten SDK-, Contract- und R4STD-Bindings.
Der fachliche Quellstand und die absichtliche Grenzaenderung stehen in
`PROVENANCE.txt`.
