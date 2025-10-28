# Dokument wymagań produktu (PRD) - 10xCards

## 1. Przegląd produktu

10xCards to webowa aplikacja do szybkiego tworzenia i nauki fiszek w oparciu o metodę spaced repetition. Rozwiązuje problem wysokiego kosztu czasowego ręcznego przygotowania jakościowych fiszek, udostępniając generowanie przez AI z dowolnego wklejonego tekstu oraz prosty edytor do tworzenia fiszek manualnych. MVP koncentruje się na jak najszybszym uzyskaniu wartości dla użytkownika przy minimalnej złożoności implementacyjnej.

Cel produktu
- Zmniejszyć czas i wysiłek potrzebny do tworzenia dobrych fiszek.
- Zwiększyć adopcję nauki metodą SRS przez integrację z gotową biblioteką open‑source.

Grupa docelowa
- Studenci, kursanci, osoby uczące się zawodowo, przygotowujące się do egzaminów lub certyfikacji.
- Zakres wiedzy: powierzchowna do średniej złożoności (Q/A, bez multimediów).

Propozycja wartości
- Wklej tekst (1–10k znaków), otrzymaj do 10 zwięzłych fiszek Q/A w języku źródłowym w mniej niż 10 s (p95).
- Edytuj i akceptuj tylko te fiszki, które chcesz zachować; odrzucone nie są zapisywane.
- Ucz się z wykorzystaniem sprawdzonego algorytmu SRS z czterostopniową oceną odpowiedzi.

Architektura wysokopoziomowa (MVP)
- Frontend: aplikacja web (desktop-first), tylko przeglądarka.
- Backend/persistencja: Supabase (uwierzytelnianie e‑mail + hasło, baza danych, proste zdarzenia/analityka).
- Generacja AI: zewnętrzny dostawca LLM; pipeline dzielenia wejścia (1–2k znaków), deduplikacja i selekcja do 10 fiszek.
- SRS: integracja z biblioteką open‑source, bez własnego algorytmu.
- Telemetria i koszty: limit 500k tokenów/dzień/użytkownik; budżet 0.1 USD/100k tokenów.

Założenia i ograniczenia
- Dostęp do pełnej funkcjonalności wyłącznie dla zalogowanych.
- Autodetekcja języka wejścia i generacja fiszek w tym samym języku; brak przełącznika języka w UI.
- Brak aplikacji mobilnych i integracji zewnętrznych na etapie MVP.

Harmonogram i zespół
- Zespół: 1 osoba.
- Czas: 3 tygodnie do MVP.


## 2. Problem użytkownika

Tworzenie wysokiej jakości fiszek jest czasochłonne i nużące, co zniechęca do korzystania z efektywnej metody nauki jaką jest spaced repetition. Użytkownicy często rezygnują na etapie przygotowania materiałów, mimo że sama metoda SRS daje wysoki zwrot z nauki. Obecne alternatywy wymagają ręcznej pracy lub skomplikowanej konfiguracji, co utrudnia start. 10xCards minimalizuje tarcie poprzez generowanie Q/A z dowolnego tekstu, szybkie akceptowanie/edytowanie kandydatów oraz natychmiastowy dostęp do powtórek.

Konsekwencje problemu
- Niska adopcja SRS ze względu na koszt przygotowania materiałów.
- Nieregularne powtórki i słabsza retencja wiedzy.
- Rozproszenie narzędzi do tworzenia i nauki, brak prostego, spójnego przepływu.


## 3. Wymagania funkcjonalne

3.1 Uwierzytelnianie i dostęp
- Uwierzytelnianie: Supabase e‑mail + hasło (logowanie, rejestracja, wylogowanie, reset hasła przez e‑mail).
- Dostęp: pełna funkcjonalność (generacja, zapis, przeglądanie, powtórki) tylko dla zalogowanych.
- Autoryzacja: użytkownik widzi i modyfikuje wyłącznie własne fiszki, własne statystyki i własne wykorzystanie tokenów.

3.2 Generowanie fiszek przez AI
- Wejście: tekst 1–10k znaków; dowolny język; autodetekcja języka; wynik w języku wejściowym.
- Format fiszek: wyłącznie Q/A; przód ≤ 200 znaków, tył ≤ 500 znaków; tekst bez multimediów.
- Liczba fiszek: AI decyduje, maksymalnie 10 na jedno żądanie.
- Interakcje: brak regeneracji zbiorczej; dla każdej fiszki dostępne akcje akceptuj, edytuj, odrzuć.
- Zapisywanie: zapisywane są wyłącznie fiszki zaakceptowane; odrzucone nie są nigdzie utrwalane.
- Pipeline generacji:
  - Dzielenie wejścia na porcje 1–2k znaków.
  - Równoległe generowanie kandydatów z poszczególnych porcji.
  - Deduplikacja podobnych pytań i selekcja najlepszych do limitu 10.
  - Gdy model zwróci >10 kandydatów, wybór 10 po usunięciu duplikatów (preferowane krótsze, bardziej ogólne pytania, pokrywające różne fragmenty treści).
- Czas i niezawodność:
  - Cel wydajności: p95 czasu generacji end‑to‑end < 10 s.
  - Timeout trybu standardowego: 6 s; przy przekroczeniu automatyczny fallback do trybu ekonomicznego dla pozostałych porcji.
  - Maksymalny łączny czas żądania: 10 s; zwróć tyle fiszek, ile wygenerowano do tego czasu.
  - Anulowanie przez użytkownika: natychmiast przerwij pozostałe porcje; zwróć częściowy wynik z gotowych porcji.
- Sytuacje skrajne:
  - 0 fiszek po przetworzeniu: wyświetl komunikat i prośbę o ponowne wprowadzenie/zmianę tekstu.
  - Przekroczenie limitu tokenów w trakcie generacji: zwróć częściowe wyniki i komunikat o limicie.
- Koszty i limity:
  - Limit dzienny: 500k tokenów na użytkownika, liczone jako suma prompt + completion.
  - Budżet: 0.1 USD/100k tokenów; tryb ekonomiczny używa tańszego modelu.

3.3 Manualne tworzenie fiszek
- Edytor Q/A z licznikami znaków i walidacją limitów (przód ≤ 200, tył ≤ 500).
- Zapis pojedynczej fiszki dla zalogowanego użytkownika z origin = manual.

3.4 Przeglądanie, edycja i usuwanie fiszek
- Lista własnych fiszek z podstawowymi informacjami (przód, fragment tyłu, data utworzenia/akceptacji, origin).
- Edycja pól Q/A z walidacją limitów; dla fiszek AI bez zmiany origin.
- Usuwanie fiszek z potwierdzeniem; usunięte nie pojawiają się w powtórkach.

3.5 Powtórki (SRS)
- Integracja z biblioteką open‑source SRS jako czarną skrzynką harmonogramującą.
- Ocena odpowiedzi w skali 4‑stopniowej: Again, Hard, Good, Easy (etykiety mogą być zlokalizowane w UI).
- Mapowanie do biblioteki: standardowe mapowanie biblioteki na due_at/interval/ease; brak własnych modyfikacji algorytmu.
- Ekran nauki wybiera karty „due” dla danego dnia; po ocenie harmonogram jest aktualizowany.
- Przy braku kart „due” wyświetlany jest jasny komunikat o braku fiszek do nauki dzisiaj.

3.6 Analityka i pomiar
- Zdarzenia minimalne:
  - card_accepted (dla fiszek AI, również po edycji), card_rejected

3.7 Model danych (MVP)
- Card: id, user_id, front_text, back_text, origin (ai|manual), accepted_at, source_language, created_at, updated_at, srs_due_at, srs_interval_days, srs_ease_factor, srs_repetitions, srs_lapses.
- ReviewLog: id, user_id, card_id, rating (again|hard|good|easy), reviewed_at, interval_days_before, interval_days_after, ease_before, ease_after.
- TokenUsage: id, user_id, date_utc, tokens_used_total.
- AnalyticsEvent: id, user_id, event_name, occurred_at, generation_request_id, properties_json.

3.8 Stany błędów i komunikaty
- 0 fiszek wygenerowanych: komunikat z instrukcją poprawy wejścia i możliwością ponowienia.
- Timeout/tryb ekonomiczny: nienachalny komunikat o częściowych wynikach i automatycznym trybie oszczędnym.
- Limit tokenów: jasny komunikat o przekroczeniu, licznik do resetu dziennego, blokada nowych generacji.
- Błędy sieci/dostawcy: przyjazny komunikat, możliwość ponowienia.


## 4. Granice produktu

W zakresie MVP
- Generowanie fiszek przez AI z wklejonego tekstu (1–10k znaków), do 10 Q/A, tekst‑only.
- Manualne tworzenie fiszek Q/A z limitami znaków i walidacją.
- Przeglądanie, edycja, usuwanie własnych fiszek; zapisywanie wyłącznie zaakceptowanych.
- Uwierzytelnianie przez Supabase; pełna funkcjonalność dostępna tylko po zalogowaniu.
- Integracja z biblioteką SRS open‑source; ocena 4‑stopniowa w powtórkach.
- Limity i koszty: 500k tokenów/dzień/użytkownik; budżet 0.1 USD/100k tokenów; p95 generacji < 10 s.

Poza zakresem MVP
- Własny, zaawansowany algorytm SRS; tuning parametrów ponad to, co ekspozytuje biblioteka.
- Import wielu formatów plików (PDF, DOCX, itp.).
- Współdzielenie zestawów fiszek i praca zespołowa.
- Integracje z zewnętrznymi platformami edukacyjnymi.
- Aplikacje mobilne; na start tylko web.
- Wyszukiwanie/kategoryzacja tagami, folderami, kolekcjami.

Ograniczenia i zależności
- Reset limitu tokenów wg czasu UTC (00:00 UTC).
- Brak przełącznika języka; język wykrywany automatycznie na podstawie wejścia.
- Zależność od dostawcy LLM i biblioteki SRS; polityka retry minimalna, bez failover między dostawcami w MVP.

Ryzyka i mitigacje
- Jakość generacji AI: twarde limity znaków i selekcja do 10 najlepszych; możliwość edycji przed akceptacją.
- Koszty: twardy dzienny limit tokenów; fallback do trybu ekonomicznego.
- Wydajność: pipeline porcji 1–2k znaków, równoległość i limit maksymalnego czasu żądania.


## 5. Historie użytkowników

US-001
Tytuł: Rejestracja i logowanie
Opis: Jako nowy użytkownik chcę utworzyć konto i się zalogować, aby mieć dostęp do generowania, zapisu i nauki fiszek.
Kryteria akceptacji:
- Można utworzyć konto e‑mail + hasło i zalogować się.
- Po zalogowaniu widać ekran generowania i własne fiszki.
- Sesja jest utrzymywana między odświeżeniami przeglądarki do czasu wylogowania.

US-002
Tytuł: Reset hasła
Opis: Jako użytkownik, który zapomniał hasła, chcę zresetować hasło przez e‑mail, aby odzyskać dostęp.
Kryteria akceptacji:
- Formularz resetu wysyła e‑mail z linkiem do ustawienia nowego hasła.
- Po ustawieniu nowego hasła mogę się zalogować tym hasłem.

US-003
Tytuł: Gating funkcji za logowaniem
Opis: Jako niezalogowany użytkownik nie powinienem móc generować ani przeglądać fiszek.
Kryteria akceptacji:
- Próba wejścia w generację lub listę fiszek przekierowuje do logowania.
- Po zalogowaniu wracam do pierwotnie żądanej funkcji.

US-004
Tytuł: Generowanie fiszek z wklejonego tekstu
Opis: Jako zalogowany użytkownik wklejam 1–10k znaków i uruchamiam generowanie, aby otrzymać do 10 fiszek Q/A w języku wejścia.
Kryteria akceptacji:
- Dla wejścia w dozwolonym zakresie otrzymuję 1–10 kandydatów Q/A (przód ≤ 200, tył ≤ 500).
- Autodetekcja języka działa; fiszki są w języku wejścia.
- Gdy model wygeneruje >10 kandydatów, widzę 10 po deduplikacji.

US-005
Tytuł: Akceptacja, edycja i odrzucenie fiszek AI
Opis: Jako użytkownik chcę akceptować, edytować lub odrzucać każdą fiszkę zanim ją zapiszę, aby kontrolować jakość.
Kryteria akceptacji:
- Akceptacja zapisuje fiszkę z origin = ai i accepted_at.
- Odrzucone fiszki nie są zapisywane i nie pojawiają się na liście.

US-006
Tytuł: Timeout i tryb ekonomiczny
Opis: Jako użytkownik chcę otrzymać częściowe wyniki oraz automatyczne przełączenie na tryb ekonomiczny po timeout, aby nie czekać zbyt długo.
Kryteria akceptacji:
- Po 6 s części niedostarczone przechodzą do trybu ekonomicznego.
- Całe żądanie kończy się do 10 s; widzę tyle fiszek, ile powstało.
- UI komunikuje tryb ekonomiczny i częściowość wyniku.

US-007
Tytuł: Anulowanie generacji
Opis: Jako użytkownik chcę móc anulować generację i otrzymać to, co już powstało.
Kryteria akceptacji:
- Kliknięcie Anuluj przerywa nowe wywołania i zwraca już gotowe fiszki.
- UI potwierdza anulowanie.

US-008
Tytuł: 0 fiszek z generacji
Opis: Jako użytkownik, gdy nie uda się wygenerować żadnej fiszki, chcę jasnego komunikatu i wskazówki co dalej.
Kryteria akceptacji:
- Pojawia się komunikat o braku fiszek i sugestia ponownego wprowadzenia lub modyfikacji tekstu.
- Brak zapisu jakichkolwiek kandydatów.

US-009
Tytuł: Limit tokenów dziennych
Opis: Jako użytkownik nie chcę przekraczać limitu 500k tokenów/dzień.
Kryteria akceptacji:
- Licznik wykorzystania tokenów uwzględnia prompt + completion.
- Po przekroczeniu limitu generacja blokuje się do resetu (00:00 UTC).
- Jeżeli limit zostanie przekroczony w trakcie generacji, otrzymuję częściowe wyniki i komunikat.

US-010
Tytuł: Tworzenie fiszek manualnie
Opis: Jako użytkownik chcę ręcznie dodać fiszkę Q/A z licznikami znaków.
Kryteria akceptacji:
- Walidacja limitów przód ≤ 200, tył ≤ 500.
- Zapisuje się fiszka z origin = manual.

US-011
Tytuł: Przeglądanie listy fiszek
Opis: Jako użytkownik chcę zobaczyć listę moich fiszek z podstawowymi informacjami i akcjami.
Kryteria akceptacji:
- Lista pokazuje przód, fragment tyłu, daty i origin.
- Lista podlega paginacji, po 10 fiszek na stronę.
- Dostępne akcje edytuj i usuń.

US-012
Tytuł: Edycja fiszki
Opis: Jako użytkownik chcę edytować treść istniejącej fiszki z zachowaniem limitów.
Kryteria akceptacji:
- Walidacja limitów znaków przy zapisie.
- Edycja fiszki odbywa się w okienku modalowym.

US-013
Tytuł: Usuwanie fiszki
Opis: Jako użytkownik chcę usunąć fiszkę, aby nie pojawiała się w nauce.
Kryteria akceptacji:
- Usunięta fiszka znika z listy i z puli SRS.
- Akcja wymaga potwierdzenia w UI.

US-014
Tytuł: Rozpoczęcie powtórki
Opis: Jako użytkownik chcę uruchomić sesję powtórkową dla kart należnych na dziś.
Kryteria akceptacji:
- System wybiera tylko karty due na dziś.
- Po każdej odpowiedzi wybieram ocenę: Again, Hard, Good, Easy.
- Harmonogram karty jest aktualizowany zgodnie z biblioteką SRS.

US-015
Tytuł: Brak kart do nauki dzisiaj
Opis: Jako użytkownik, gdy nie mam kart na dziś, chcę jasny komunikat.
Kryteria akceptacji:
- Ekran powtórek wyświetla informację o braku kart due i proponuje powrót do tworzenia.

US-016
Tytuł: Autodetekcja języka
Opis: Jako użytkownik chcę, aby fiszki były generowane w języku wejścia bez ręcznego wyboru.
Kryteria akceptacji:
- Wklejenie tekstu w danym języku skutkuje fiszkami w tym samym języku.
- Brak przełącznika języka w UI.

US-017
Tytuł: Zdarzenia analityczne
Opis: Jako właściciel produktu chcę widzieć zdarzenia generacji, akceptacji, odrzucenia i nauki, aby mierzyć cele.
Kryteria akceptacji:
- Emisja zdarzeń: card_accepted/rejected;
- Zdarzenia zawierają user_id.
- Retencja co najmniej 90 dni.

US-018
Tytuł: Wydajność generacji
Opis: Jako użytkownik chcę, aby generacja kończyła się szybko, abym nie tracił czasu.
Kryteria akceptacji:
- p95 czasu end‑to‑end < 10 s mierzony telemetrią.
- Brak wiszących żądań powyżej 10 s.


## 6. Metryki sukcesu

Definicje i sposób pomiaru
- 75% fiszek AI akceptowanych przez użytkowników:
  - Wzór: liczba card_accepted / liczba kandydatów przedstawionych użytkownikowi (card_accepted + card_rejected).
  - Wymaga zdarzeń card_accepted/card_rejected.
- 75% wszystkich zapisanych fiszek pochodzi z AI:
  - Wzór: liczba zapisanych fiszek z origin = ai / liczba wszystkich zapisanych fiszek.
  - Wymaga zapisu pola origin i liczenia na przestrzeni czasu.
- p95 < 10 s dla generacji:
  - Wzór: 95. percentyl czasu od kliknięcia Generuj do pojawienia się kandydatów w UI.
  - Telemetria czasu start/koniec po stronie klienta i korelacja generation_request_id.
- Kontrola kosztów i wykorzystania:
  - Tokeny per użytkownik/dzień: licznik prompt + completion; reset 00:00 UTC.
  - Odsetek żądań w trybie ekonomicznym po timeout: monitorowany tygodniowo.

Uwagi wdrożeniowe do metryk
- Dane zdarzeń przechowywane min. 90 dni, z user_id i generation_request_id.
- Weryfikacja poprawności przez próby ręczne i porównanie z logami systemowymi.
