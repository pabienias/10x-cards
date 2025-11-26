# Schemat bazy danych PostgreSQL - 10xCards

## 1. Tabele z kolumnami, typami danych i ograniczeniami

### 1.0 auth.users (zarządzana przez Supabase)

**Status:** Tabela zarządzana automatycznie przez Supabase Auth - NIE tworzymy jej ręcznie.

**Opis:** Główna tabela użytkowników w schemacie `auth`, zawierająca dane uwierzytelniania i profili użytkowników. Jest podstawą dla wszystkich relacji w aplikacji.

**Najważniejsze kolumny (do których się odwołujemy):**

- `id` - UUID, klucz główny, unikalny identyfikator użytkownika
- `email` - TEXT, adres e-mail użytkownika (unikalny)
- `encrypted_password` - TEXT, zahashowane hasło
- `email_confirmed_at` - TIMESTAMPTZ, timestamp potwierdzenia e-maila
- `created_at` - TIMESTAMPTZ, data utworzenia konta
- `updated_at` - TIMESTAMPTZ, data ostatniej aktualizacji

**Funkcje pomocnicze Supabase:**

- `auth.uid()` - zwraca UUID aktualnie zalogowanego użytkownika, używana w politykach RLS
- `auth.email()` - zwraca e-mail aktualnie zalogowanego użytkownika

**Uwagi dotyczące integracji:**

- Wszystkie tabele aplikacyjne mają FK `user_id` wskazujący na `auth.users(id)`
- Supabase automatycznie zarządza: rejestrację, logowanie, reset hasła, sesje, tokeny
- Nie modyfikujemy tej tabeli bezpośrednio - korzystamy z Supabase Auth API
- Usunięcie użytkownika z `auth.users` kaskadowo usuwa wszystkie jego dane (ON DELETE CASCADE w tabelach aplikacyjnych)
- Polityki RLS w tabelach aplikacyjnych używają `auth.uid()` do identyfikacji aktualnego użytkownika

**Metody uwierzytelniania w MVP:**

- E-mail + hasło (podstawowa metoda)
- Reset hasła przez e-mail
- Sesje z automatycznym odświeżaniem tokenu

**Dostęp do danych użytkownika:**

- Client-side: przez `supabase.auth.getUser()` lub `supabase.auth.getSession()`
- Server-side: przez `createServerComponentClient()` z automatycznym context
- Publiczne profile (jeśli potrzebne w przyszłości): osobna tabela `public.profiles` z FK do `auth.users(id)`

### 1.1 cards

**Opis:** Główna tabela przechowująca fiszki użytkowników (zarówno generowane przez AI jak i manualne).

**Kolumny:**

- `id` - UUID, klucz główny, domyślnie generowany przez `gen_random_uuid()`
- `user_id` - UUID, NOT NULL, klucz obcy do `auth.users(id)` z kaskadowym usuwaniem (ON DELETE CASCADE)
- `origin` - TEXT, NOT NULL, tylko wartości: 'ai' lub 'manual' (CHECK constraint)
- `front_text` - TEXT, NOT NULL, długość > 0 i ≤ 200 znaków (CHECK constraint)
- `back_text` - TEXT, NOT NULL, długość > 0 i ≤ 500 znaków (CHECK constraint)
- `source_language` - TEXT, NULL, wymagany dla origin='ai', NULL dla origin='manual'
- `generation_request_id` - UUID, NULL, klucz obcy do `generation_requests(id)`, wymagany dla origin='ai'
- `accepted_at` - TIMESTAMPTZ, NULL, timestamp akceptacji fiszki, wymagany dla origin='ai', NULL dla origin='manual'
- `created_at` - TIMESTAMPTZ, NOT NULL, domyślnie `now()`
- `updated_at` - TIMESTAMPTZ, NOT NULL, domyślnie `now()`, automatycznie aktualizowane przez trigger
- `deleted_at` - TIMESTAMPTZ, NULL, soft-delete marker (NULL = aktywna, NOT NULL = usunięta)

**Ograniczenia:**

- Constraint `cards_ai_fields_check`: zapewnia spójność pól zależnych od origin:
  - Jeśli origin = 'ai': `source_language`, `generation_request_id` i `accepted_at` muszą być NOT NULL
  - Jeśli origin = 'manual': `source_language`, `generation_request_id` i `accepted_at` muszą być NULL
- Unique constraint na parze `(id, user_id)` - wymagane dla złożonego FK w `review_logs`

**Komentarze:**

- Tabela: "Fiszki użytkowników - zarówno wygenerowane przez AI jak i utworzone manualnie"
- `origin`: "Źródło fiszki: ai (generowana) lub manual (ręczna)"
- `front_text`: "Przód fiszki (pytanie), max 200 znaków"
- `back_text`: "Tył fiszki (odpowiedź), max 500 znaków"
- `source_language`: "Język źródłowy (wymagany dla AI, NULL dla manual)"
- `generation_request_id`: "FK do generation_requests (tylko dla origin=ai)"
- `accepted_at`: "Timestamp akceptacji fiszki AI (tylko dla origin=ai)"
- `deleted_at`: "Soft-delete: NULL = aktywna, NOT NULL = usunięta"

### 1.2 generation_requests

**Opis:** Telemetria żądań generacji fiszek przez AI.

**Kolumny:**

- `id` - UUID, klucz główny, domyślnie generowany przez `gen_random_uuid()`
- `user_id` - UUID, NOT NULL, klucz obcy do `auth.users(id)` z kaskadowym usuwaniem (ON DELETE CASCADE)
- `model` - TEXT, NOT NULL, identyfikator modelu AI użytego do generacji
- `status` - TEXT, NOT NULL, tylko wartości: 'success', 'partial', 'cancelled', 'error' (CHECK constraint)
- `started_at` - TIMESTAMPTZ, NOT NULL, domyślnie `now()`
- `computation_time_ms` - INTEGER, NULL, całkowity czas obliczeń w milisekundach, ≥ 0 (CHECK constraint)
- `generated_count` - INTEGER, NOT NULL, domyślnie 0, liczba wygenerowanych kandydatów (po deduplikacji, max 10), ≥ 0 (CHECK constraint)
- `accepted_unedited_count` - INTEGER, NOT NULL, domyślnie 0, liczba zaakceptowanych fiszek bez edycji, ≥ 0 (CHECK constraint)
- `accepted_edited_count` - INTEGER, NOT NULL, domyślnie 0, liczba zaakceptowanych fiszek po edycji, ≥ 0 (CHECK constraint)
- `error_code` - TEXT, NULL, kod błędu w przypadku niepowodzenia

**Komentarze:**

- Tabela: "Historia i telemetria żądań generacji fiszek przez AI"
- `model`: "Identyfikator modelu AI użytego do generacji"
- `status`: "Status generacji: success, partial, cancelled, error"
- `computation_time_ms`: "Całkowity czas obliczeń w milisekundach"
- `generated_count`: "Liczba wygenerowanych kandydatów (po deduplikacji, max 10)"
- `accepted_unedited_count`: "Liczba zaakceptowanych fiszek bez edycji"
- `accepted_edited_count`: "Liczba zaakceptowanych fiszek po edycji"

### 1.3 review_logs

**Opis:** Historia przeglądów i ocen fiszek podczas sesji nauki (SRS).

**Kolumny:**

- `id` - UUID, klucz główny, domyślnie generowany przez `gen_random_uuid()`
- `user_id` - UUID, NOT NULL, klucz obcy do `auth.users(id)` z kaskadowym usuwaniem (ON DELETE CASCADE)
- `card_id` - UUID, NOT NULL, część złożonego klucza obcego
- `rating` - TEXT, NOT NULL, tylko wartości: 'again', 'hard', 'good', 'easy' (CHECK constraint)
- `reviewed_at` - TIMESTAMPTZ, NOT NULL, domyślnie `now()`
- `interval_days_before` - INTEGER, NULL, interwał w dniach przed oceną (NULL w MVP), ≥ 0 (CHECK constraint)
- `interval_days_after` - INTEGER, NULL, interwał w dniach po ocenie (NULL w MVP), ≥ 0 (CHECK constraint)
- `ease_before` - NUMERIC(5,2), NULL, współczynnik łatwości przed oceną (NULL w MVP), ≥ 1.0 (CHECK constraint)
- `ease_after` - NUMERIC(5,2), NULL, współczynnik łatwości po ocenie (NULL w MVP), ≥ 1.0 (CHECK constraint)

**Ograniczenia:**

- Złożony klucz obcy `(card_id, user_id)` wskazujący na `cards(id, user_id)` z ON DELETE RESTRICT - zapewnia zgodność user_id i uniemożliwia fizyczne usunięcie fiszki z historią przeglądów

**Komentarze:**

- Tabela: "Historia ocen fiszek podczas sesji nauki (spaced repetition)"
- `rating`: "Ocena trudności: again, hard, good, easy"
- `interval_days_before`: "Interwał w dniach przed oceną (NULL w MVP)"
- `interval_days_after`: "Interwał w dniach po ocenie (NULL w MVP)"
- `ease_before`: "Współczynnik łatwości przed oceną (NULL w MVP)"
- `ease_after`: "Współczynnik łatwości po ocenie (NULL w MVP)"

### 1.4 token_usage

**Opis:** Zliczanie wykorzystania tokenów AI per użytkownik per dzień (limit 500k/dzień).

**Kolumny:**

- `user_id` - UUID, NOT NULL, część klucza głównego, klucz obcy do `auth.users(id)` z kaskadowym usuwaniem (ON DELETE CASCADE)
- `date_utc` - DATE, NOT NULL, część klucza głównego, data UTC (bez czasu)
- `tokens_used_total` - BIGINT, NOT NULL, domyślnie 0, suma tokenów (prompt + completion) zużytych danego dnia, ≥ 0 (CHECK constraint)

**Ograniczenia:**

- Klucz główny: kompozytowy `(user_id, date_utc)` - zapewnia unikatowość per użytkownik per dzień, umożliwia UPSERT

**Komentarze:**

- Tabela: "Zliczanie wykorzystania tokenów AI per użytkownik per dzień UTC"
- `date_utc`: "Data UTC (bez czasu)"
- `tokens_used_total`: "Suma tokenów (prompt + completion) zużytych danego dnia"

### 1.5 analytics_events

**Opis:** Zdarzenia analityczne dla mierzenia metryk produktowych (retencja 90 dni).

**Kolumny:**

- `id` - UUID, klucz główny, domyślnie generowany przez `gen_random_uuid()`
- `user_id` - UUID, NOT NULL, klucz obcy do `auth.users(id)` z kaskadowym usuwaniem (ON DELETE CASCADE)
- `event_name` - TEXT, NOT NULL, tylko wartości: 'card_accepted', 'card_rejected' (CHECK constraint)
- `occurred_at` - TIMESTAMPTZ, NOT NULL, domyślnie `now()`
- `card_id` - UUID, NULL, klucz obcy do `cards(id)` z ON DELETE SET NULL (opcjonalne powiązanie)
- `generation_request_id` - UUID, NULL, klucz obcy do `generation_requests(id)` z ON DELETE SET NULL (opcjonalne powiązanie)
- `properties_json` - JSONB, NULL, dodatkowe właściwości zdarzenia w formacie JSON

**Ograniczenia:**

- Constraint `analytics_events_name_check`: ogranicza wartości `event_name` do: 'card_accepted', 'card_rejected'

**Komentarze:**

- Tabela: "Zdarzenia analityczne dla metryk produktowych (retencja 90 dni)"
- `event_name`: "Typ zdarzenia: card_accepted, card_rejected"
- `properties_json`: "Dodatkowe właściwości zdarzenia w formacie JSON"

### 1.6 srs_states (poza zakresem MVP)

**Status:** Tabela zaplanowana na przyszłość, NIE implementowana w MVP.

**Opis:** Stany SRS dla poszczególnych fiszek - harmonogramowanie powtórek.

**Planowane kolumny:**

- `id` - UUID, klucz główny
- `user_id` - UUID, NOT NULL, FK do auth.users
- `card_id` - UUID, NOT NULL, część złożonego FK
- `due_at` - TIMESTAMPTZ, NOT NULL, data/czas następnej powtórki
- `interval_days` - INTEGER, NOT NULL, aktualny interwał w dniach
- `ease_factor` - NUMERIC(5,2), NOT NULL, współczynnik łatwości
- `repetitions` - INTEGER, NOT NULL, liczba powtórzeń
- `lapses` - INTEGER, NOT NULL, liczba nieudanych prób
- `created_at`, `updated_at` - TIMESTAMPTZ, NOT NULL

**Planowane ograniczenia:**

- Złożony FK `(card_id, user_id)` do `cards(id, user_id)` z ON DELETE CASCADE
- Unique constraint na `(card_id, user_id)` - jedna karta = jeden stan SRS

## 2. Relacje między tabelami

### 2.1 Diagram relacji

```
auth.users (Supabase)
    ║
    ╠══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║ 1:N                                                      ║ 1:N
    ▼                                                          ▼
cards                                                  generation_requests
    ║                                                          ▲
    ║ N:1 (tylko dla origin='ai')                              ║
    ╚══════════════════════════════════════════════════════════╝
    ║
    ║ 1:N                auth.users
    ▼                        ║
review_logs                  ║ 1:N
(złożony FK:                 ▼
 card_id+user_id)       token_usage
                             ║
            auth.users       ║
                ║            ║
                ║ 1:N        ║
                ▼            ║
         analytics_events ◄══╝
```

### 2.2 Szczegóły relacji

| Tabela źródłowa | Kardynalność | Tabela docelowa | Klucz obcy | Akcja przy usuwaniu | Opis |
|----------------|--------------|-----------------|------------|---------------------|------|
| auth.users | 1:N | cards | `user_id` | CASCADE | Każdy użytkownik może mieć wiele fiszek. Usunięcie użytkownika usuwa wszystkie jego fiszki. |
| auth.users | 1:N | generation_requests | `user_id` | CASCADE | Każdy użytkownik może mieć wiele żądań generacji. Usunięcie użytkownika usuwa wszystkie jego żądania. |
| auth.users | 1:N | token_usage | `user_id` (część PK) | CASCADE | Każdy użytkownik ma wiele rekordów wykorzystania tokenów (per dzień). Usunięcie użytkownika usuwa jego historię tokenów. |
| auth.users | 1:N | analytics_events | `user_id` | CASCADE | Każdy użytkownik generuje wiele zdarzeń analitycznych. Usunięcie użytkownika usuwa jego zdarzenia. |
| generation_requests | 1:N | cards | `generation_request_id` | brak akcji* | Jedno żądanie generacji może utworzyć wiele fiszek (tylko dla origin='ai'). *FK nie jest wymuszony na poziomie DB. |
| cards | 1:N | review_logs | `(card_id, user_id)` złożony | RESTRICT | Jedna fiszka może mieć wiele ocen/przeglądów. Nie można fizycznie usunąć fiszki z historią - wymusza soft-delete. |
| cards | 1:N | analytics_events | `card_id` | SET NULL | Jedna fiszka może być powiązana z wieloma zdarzeniami (opcjonalnie). Usunięcie fiszki zachowuje zdarzenia. |
| generation_requests | 1:N | analytics_events | `generation_request_id` | SET NULL | Jedno żądanie może być powiązane z wieloma zdarzeniami (opcjonalnie). Usunięcie żądania zachowuje zdarzenia. |

**Uwagi:**

- Wszystkie relacje do `auth.users` używają `ON DELETE CASCADE` - usunięcie użytkownika usuwa wszystkie jego dane
- `review_logs` używa `ON DELETE RESTRICT` dla `card_id` - nie można fizycznie usunąć fiszki z historią przeglądów, wymusza soft-delete
- `analytics_events` używa `ON DELETE SET NULL` dla `card_id` i `generation_request_id` - zachowanie zdarzeń nawet po usunięciu powiązanych encji (dla audytu)
- Brak relacji N:N - wszystkie relacje są 1:N
- Złożony FK w `review_logs` `(card_id, user_id)` → `cards(id, user_id)` zapewnia, że użytkownik może oceniać tylko własne fiszki

## 3. Indeksy

### 3.1 Indeksy dla tabeli cards

**Indeks:** `idx_cards_user_date_active`
- **Kolumny:** `user_id`, `COALESCE(accepted_at, created_at) DESC`, `id DESC`
- **Typ:** B-tree, częściowy (WHERE `deleted_at IS NULL`)
- **Przeznaczenie:** Główny indeks dla list fiszek użytkownika z paginacją i sortowaniem po dacie akceptacji/utworzenia. Wspiera keyset pagination.

**Indeks:** `idx_cards_user_active`
- **Kolumny:** `user_id`
- **Typ:** B-tree, częściowy (WHERE `deleted_at IS NULL`)
- **Przeznaczenie:** Szybkie filtrowanie aktywnych fiszek użytkownika (zliczanie, proste listy).

**Indeks:** `idx_cards_generation_request`
- **Kolumny:** `generation_request_id`
- **Typ:** B-tree, częściowy (WHERE `deleted_at IS NULL` AND `origin = 'ai'`)
- **Przeznaczenie:** Znajdowanie fiszek z konkretnego żądania generacji (dla statystyk i szczegółów generacji).

**Indeks:** `idx_cards_deleted_at`
- **Kolumny:** `deleted_at`
- **Typ:** B-tree, częściowy (WHERE `deleted_at IS NOT NULL`)
- **Przeznaczenie:** Optymalizacja zapytań dotyczących soft-deleted fiszek (audyt, analiza, potencjalne przywracanie przez admin).

### 3.2 Indeksy dla tabeli generation_requests

**Indeks:** `idx_generation_requests_user_started`
- **Kolumny:** `user_id`, `started_at DESC`
- **Typ:** B-tree
- **Przeznaczenie:** Historia generacji użytkownika posortowana chronologicznie (dashboard, statystyki użytkownika).

**Indeks:** `idx_generation_requests_status`
- **Kolumny:** `status`, `started_at DESC`
- **Typ:** B-tree
- **Przeznaczenie:** Analiza statusów generacji (monitoring błędów, partial results, sukces rate) posortowana chronologicznie.

### 3.3 Indeksy dla tabeli review_logs

**Indeks:** `idx_review_logs_user_reviewed`
- **Kolumny:** `user_id`, `reviewed_at DESC`
- **Typ:** B-tree
- **Przeznaczenie:** Historia przeglądów użytkownika posortowana chronologicznie (statystyki nauki, timeline aktywności).

**Indeks:** `idx_review_logs_card`
- **Kolumny:** `card_id`, `reviewed_at DESC`
- **Typ:** B-tree
- **Przeznaczenie:** Historia przeglądów konkretnej fiszki (szczegóły fiszki, tracking postępu dla danej karty).

**Indeks:** `idx_review_logs_rating`
- **Kolumny:** `rating`, `reviewed_at DESC`
- **Typ:** B-tree
- **Przeznaczenie:** Analiza ocen (ile again/hard/good/easy w systemie, identyfikacja trudnych fiszek).

### 3.4 Indeksy dla tabeli token_usage

**Indeks:** `idx_token_usage_user_date`
- **Kolumny:** `user_id`, `date_utc DESC`
- **Typ:** B-tree (opcjonalny, jeśli PK nie wystarcza)
- **Przeznaczenie:** Sprawdzanie limitu dziennego i historii wykorzystania tokenów użytkownika.
- **Uwaga:** Klucz główny `(user_id, date_utc)` automatycznie tworzy indeks, dodatkowy indeks może nie być potrzebny.

### 3.5 Indeksy dla tabeli analytics_events

**Indeks:** `idx_analytics_events_user_name_occurred`
- **Kolumny:** `user_id`, `event_name`, `occurred_at DESC`
- **Typ:** B-tree
- **Przeznaczenie:** Filtrowanie zdarzeń użytkownika po typie i dacie (statystyki użytkownika, analiza akceptacji/odrzuceń).

**Indeks:** `idx_analytics_events_occurred`
- **Kolumny:** `occurred_at`
- **Typ:** B-tree
- **Przeznaczenie:** Zadanie retencyjne - szybkie usuwanie zdarzeń starszych niż 90 dni (WHERE `occurred_at < now() - interval '90 days'`).

**Indeks:** `idx_analytics_events_card`
- **Kolumny:** `card_id`, `occurred_at DESC`
- **Typ:** B-tree, częściowy (WHERE `card_id IS NOT NULL`)
- **Przeznaczenie:** Analiza zdarzeń powiązanych z konkretną fiszką (timeline fiszki, audyt).

**Indeks:** `idx_analytics_events_generation`
- **Kolumny:** `generation_request_id`, `occurred_at DESC`
- **Typ:** B-tree, częściowy (WHERE `generation_request_id IS NOT NULL`)
- **Przeznaczenie:** Analiza zdarzeń powiązanych z konkretnym żądaniem generacji (success rate per request).

**Indeks (opcjonalny):** `idx_analytics_events_properties`
- **Kolumny:** `properties_json`
- **Typ:** GIN (Generalized Inverted Index)
- **Przeznaczenie:** Szybkie wyszukiwanie po właściwościach w JSONB (jeśli będzie potrzeba filtrowania/wyszukiwania po kluczach/wartościach w properties_json).

### 3.6 Uwagi dotyczące indeksów

- **Indeksy częściowe:** Używane tam gdzie możliwe (szczególnie dla `deleted_at IS NULL` w cards) - mniejsze, szybsze, tylko dla aktywnych rekordów
- **Sortowanie DESC:** Dla kolumn timestamp w indeksach - większość query będzie pobierać najnowsze rekordy
- **Keyset pagination:** Indeks `idx_cards_user_date_active` wspiera wydajną paginację bez OFFSET
- **GIN dla JSONB:** Opcjonalny, dodać tylko jeśli będzie rzeczywista potrzeba wyszukiwania w properties_json

## 4. Zasady Row Level Security (RLS)

### 4.1 Włączenie RLS

RLS musi być włączony na wszystkich tabelach aplikacyjnych:
- `cards`
- `generation_requests`
- `review_logs`
- `token_usage`
- `analytics_events`

### 4.2 Polityki RLS dla tabeli cards

**Polityka SELECT dla authenticated users:** `cards_select_policy`
- **Operacja:** SELECT
- **Rola:** authenticated
- **Warunek:** `user_id = auth.uid() AND deleted_at IS NULL`
- **Opis:** Użytkownik widzi tylko swoje aktywne fiszki (soft-deleted są ukryte).

**Polityka SELECT dla service_role:** `cards_select_service_policy`
- **Operacja:** SELECT
- **Rola:** service_role
- **Warunek:** `true` (bez ograniczeń)
- **Opis:** Service role ma dostęp do wszystkich fiszek włącznie z soft-deleted (dla audytu, analiz, migracji).

**Polityka INSERT dla authenticated users:** `cards_insert_policy`
- **Operacja:** INSERT
- **Rola:** authenticated
- **Warunek WITH CHECK:** `user_id = auth.uid()`
- **Opis:** Użytkownik może tworzyć tylko fiszki z własnym user_id.

**Polityka UPDATE dla authenticated users:** `cards_update_policy`
- **Operacja:** UPDATE
- **Rola:** authenticated
- **Warunek USING:** `user_id = auth.uid() AND deleted_at IS NULL`
- **Warunek WITH CHECK:** `user_id = auth.uid()`
- **Opis:** Użytkownik może aktualizować tylko swoje aktywne fiszki. Soft-delete też używa UPDATE (ustawienie deleted_at).

**DELETE:** Brak polityki DELETE dla authenticated users - tylko soft-delete przez UPDATE. Fizyczne DELETE dostępne tylko dla service_role (bez osobnej polityki, przez brak polityki DELETE dla innych).

### 4.3 Polityki RLS dla tabeli generation_requests

**Polityka SELECT dla authenticated users:** `generation_requests_select_policy`
- **Operacja:** SELECT
- **Rola:** authenticated
- **Warunek:** `user_id = auth.uid()`
- **Opis:** Użytkownik widzi tylko swoje żądania generacji.

**Polityka SELECT dla service_role:** `generation_requests_select_service_policy`
- **Operacja:** SELECT
- **Rola:** service_role
- **Warunek:** `true`
- **Opis:** Service role ma dostęp do wszystkich żądań (monitoring, analytics).

**Polityka INSERT dla authenticated users:** `generation_requests_insert_policy`
- **Operacja:** INSERT
- **Rola:** authenticated
- **Warunek WITH CHECK:** `user_id = auth.uid()`
- **Opis:** Użytkownik może tworzyć tylko swoje żądania generacji.

**Polityka UPDATE dla authenticated users:** `generation_requests_update_policy`
- **Operacja:** UPDATE
- **Rola:** authenticated
- **Warunek USING:** `user_id = auth.uid()`
- **Warunek WITH CHECK:** `user_id = auth.uid()`
- **Opis:** Użytkownik może aktualizować tylko swoje żądania (np. zliczanie po akceptacji fiszek).

**Polityka UPDATE dla service_role:** `generation_requests_update_service_policy`
- **Operacja:** UPDATE
- **Rola:** service_role
- **Warunek:** `true`
- **Opis:** Service role może aktualizować wszystkie żądania (korekty, migracje).

### 4.4 Polityki RLS dla tabeli review_logs

**Polityka SELECT dla authenticated users:** `review_logs_select_policy`
- **Operacja:** SELECT
- **Rola:** authenticated
- **Warunek:** `user_id = auth.uid()`
- **Opis:** Użytkownik widzi tylko swoje logi przeglądów.

**Polityka SELECT dla service_role:** `review_logs_select_service_policy`
- **Operacja:** SELECT
- **Rola:** service_role
- **Warunek:** `true`
- **Opis:** Service role ma dostęp do wszystkich logów (analytics, research).

**Polityka INSERT dla authenticated users:** `review_logs_insert_policy`
- **Operacja:** INSERT
- **Rola:** authenticated
- **Warunek WITH CHECK:** `user_id = auth.uid()`
- **Opis:** Użytkownik może tworzyć tylko swoje logi. Złożony FK dodatkowo wymusza zgodność card_id z user_id.

**DELETE/UPDATE:** Brak polityk - logi są niemutowalne po zapisie (append-only). Tylko service_role może je modyfikować (korekty, czyszczenie) przez brak polityk dla innych ról.

### 4.5 Polityki RLS dla tabeli token_usage

**Polityka SELECT dla authenticated users:** `token_usage_select_policy`
- **Operacja:** SELECT
- **Rola:** authenticated
- **Warunek:** `user_id = auth.uid()`
- **Opis:** Użytkownik widzi tylko swoje wykorzystanie tokenów.

**Polityka SELECT dla service_role:** `token_usage_select_service_policy`
- **Operacja:** SELECT
- **Rola:** service_role
- **Warunek:** `true`
- **Opis:** Service role ma dostęp do wszystkich rekordów (billing, monitoring limitów).

**Polityka INSERT dla authenticated users:** `token_usage_insert_policy`
- **Operacja:** INSERT
- **Rola:** authenticated
- **Warunek WITH CHECK:** `user_id = auth.uid()`
- **Opis:** Użytkownik może tworzyć tylko swoje rekordy (część operacji UPSERT).

**Polityka UPDATE dla authenticated users:** `token_usage_update_policy`
- **Operacja:** UPDATE
- **Rola:** authenticated
- **Warunek USING:** `user_id = auth.uid()`
- **Warunek WITH CHECK:** `user_id = auth.uid()`
- **Opis:** Użytkownik może aktualizować tylko swoje rekordy (część operacji UPSERT przy zwiększaniu licznika).

**Polityka UPDATE dla service_role:** `token_usage_update_service_policy`
- **Operacja:** UPDATE
- **Rola:** service_role
- **Warunek:** `true`
- **Opis:** Service role może aktualizować wszystkie rekordy (korekty, resety).

### 4.6 Polityki RLS dla tabeli analytics_events

**Polityka SELECT dla authenticated users:** `analytics_events_select_policy`
- **Operacja:** SELECT
- **Rola:** authenticated
- **Warunek:** `user_id = auth.uid()`
- **Opis:** Użytkownik widzi tylko swoje zdarzenia (jeśli będzie potrzeba pokazywania własnej aktywności).

**Polityka SELECT dla service_role:** `analytics_events_select_service_policy`
- **Operacja:** SELECT
- **Rola:** service_role
- **Warunek:** `true`
- **Opis:** Service role ma dostęp do wszystkich zdarzeń (analytics, raportowanie).

**Polityka INSERT dla authenticated users:** `analytics_events_insert_policy`
- **Operacja:** INSERT
- **Rola:** authenticated
- **Warunek WITH CHECK:** `user_id = auth.uid()`
- **Opis:** Użytkownik może tworzyć tylko swoje zdarzenia (emitowane z frontendu lub API).

**Polityka INSERT dla service_role:** `analytics_events_insert_service_policy`
- **Operacja:** INSERT
- **Rola:** service_role
- **Warunek:** `true`
- **Opis:** Service role może tworzyć wszystkie zdarzenia (zdarzenia systemowe, import).

**Polityka DELETE dla service_role:** `analytics_events_delete_service_policy`
- **Operacja:** DELETE
- **Rola:** service_role
- **Warunek:** `true`
- **Opis:** Service role może usuwać zdarzenia (zadanie retencyjne 90 dni).

### 4.7 Uwagi dotyczące RLS

- **Bezpieczeństwo:** Wszystkie operacje są ograniczone do `user_id = auth.uid()` dla authenticated users - użytkownik nie ma dostępu do danych innych użytkowników
- **Service role:** Osobne polityki z pełnym dostępem (`USING (true)`) dla operacji systemowych, migracji, analiz, czyszczenia
- **Złożony FK:** W `review_logs` dodatkowo wymusza zgodność przez constraint - nawet jeśli RLS byłby omyłkowo wyłączony, FK chroni przed ocenianiem cudzych fiszek
- **Soft-delete:** RLS dla cards filtruje `deleted_at IS NULL` - użytkownik nie widzi soft-deleted fiszek, ale service_role tak
- **Append-only:** `review_logs` i `analytics_events` - brak polityk UPDATE/DELETE dla authenticated - niemutowalne po zapisie

## 5. Funkcje i triggery pomocnicze

### 5.1 Funkcja automatycznej aktualizacji updated_at

**Nazwa:** `update_updated_at_column()`

**Typ:** TRIGGER function

**Język:** plpgsql

**Logika:**
- Przy każdym UPDATE na rekordzie automatycznie ustawia `NEW.updated_at = now()`
- Zwraca `NEW` (zmodyfikowany rekord)

**Zastosowanie:** Automatyczne śledzenie czasu ostatniej modyfikacji rekordu bez konieczności ręcznego ustawiania w każdym query.

### 5.2 Trigger dla automatycznej aktualizacji updated_at

**Nazwa:** `cards_updated_at_trigger`

**Tabela:** `cards`

**Timing:** BEFORE UPDATE

**Level:** FOR EACH ROW

**Funkcja:** `update_updated_at_column()`

**Opis:** Automatycznie aktualizuje pole `updated_at` w tabeli cards przy każdej modyfikacji rekordu (włącznie z soft-delete).

**Uwaga:** Ten sam trigger można dodać do innych tabel z polem `updated_at` (np. przyszła tabela `srs_states`).

### 5.3 Funkcja walidacji soft-delete

**Nazwa:** `validate_card_soft_delete()`

**Typ:** TRIGGER function

**Język:** plpgsql

**Logika:**

1. **Ochrona przed przywracaniem soft-deleted fiszek:**
   - Jeśli `OLD.deleted_at IS NOT NULL` AND `NEW.deleted_at IS NULL`
   - To RAISE EXCEPTION 'Cannot restore soft-deleted cards. Create a new card instead.'
   - Powód: Przywracanie mogłoby powodować problemy z integralnością (FK w review_logs), lepiej utworzyć nową fiszkę

2. **Ochrona przed edycją pól podczas soft-delete:**
   - Jeśli `NEW.deleted_at IS NOT NULL` AND `OLD.deleted_at IS NULL` (operacja soft-delete)
   - Sprawdź czy jakiekolwiek pole oprócz `deleted_at` i `updated_at` zostało zmienione
   - Jeśli tak, to RAISE EXCEPTION 'Cannot modify card fields during soft-delete operation'
   - Powód: Soft-delete powinien być atomową operacją tylko na `deleted_at`, bez równoczesnych zmian treści

3. **Zwraca:** `NEW` jeśli walidacja przeszła pomyślnie

### 5.4 Trigger dla walidacji soft-delete

**Nazwa:** `cards_soft_delete_trigger`

**Tabela:** `cards`

**Timing:** BEFORE UPDATE

**Level:** FOR EACH ROW

**Funkcja:** `validate_card_soft_delete()`

**Opis:** Wymusza poprawne zachowanie soft-delete - tylko ustawienie `deleted_at`, bez przywracania i bez jednoczesnych zmian innych pól.

### 5.5 Funkcja czyszcząca stare zdarzenia analityczne

**Nazwa:** `cleanup_old_analytics_events()`

**Typ:** Standalone function

**Zwraca:** void

**Język:** plpgsql

**Security:** SECURITY DEFINER (wykonuje się z uprawnieniami twórcy funkcji, potrzebne dla DELETE mimo RLS)

**Logika:**
- DELETE FROM `analytics_events` WHERE `occurred_at < now() - interval '90 days'`
- Usuwa wszystkie zdarzenia starsze niż 90 dni (retencja zgodna z PRD)

**Uruchamianie:**
- Przez zewnętrzny cron job (preferowane - np. GitHub Actions, Vercel Cron)
- Lub przez pg_cron extension w Supabase: `SELECT cron.schedule('cleanup-analytics', '0 2 * * *', 'SELECT cleanup_old_analytics_events()')`
- Rekomendowane: codziennie o 2:00 UTC

**Uwaga:** Wymaga uprawnień service_role do wykonania DELETE mimo polityk RLS (dlatego SECURITY DEFINER).

### 5.6 Uwagi dotyczące funkcji i triggerów

- **Kolejność triggerów:** `validate_card_soft_delete` → `update_updated_at_column` (oba BEFORE UPDATE, kolejność alfabetyczna nazw)
- **Performance:** Triggery są bardzo lekkie (proste przypisania), nie powinny wpływać na wydajność
- **Testowanie:** Należy przetestować scenariusze:
  - Próba przywrócenia soft-deleted fiszki (powinien być błąd)
  - Próba edycji treści podczas soft-delete (powinien być błąd)
  - Poprawny soft-delete (tylko deleted_at) - powinno działać
  - Automatyczna aktualizacja updated_at przy każdej edycji
- **Retencja:** Monitorować wykonanie cleanup_old_analytics_events i czas wykonania (jeśli będzie dużo zdarzeń, może być potrzebne partycjonowanie lub batching)

## 6. Dodatkowe uwagi i decyzje projektowe

### 6.1 Wybór typów danych

- **UUID dla PK:** Używamy `gen_random_uuid()` dla wszystkich kluczy głównych
  - Bezpieczeństwo: brak wycieków informacji o liczbie rekordów (ID nie są sekwencyjne)
  - Integracja: łatwość generowania UUID na frontendzie przed zapisem (optimistic UI)
  - Distributed-friendly: brak konfliktów przy replikacji/sharding w przyszłości

- **timestamptz:** Wszystkie pola czasowe używają `timestamptz` (timezone-aware)
  - Zawsze przechowywane w UTC w bazie
  - Automatyczna konwersja przy odczycie do timezone klienta jeśli potrzeba
  - Unikanie błędów związanych z DST i strefami czasowymi

- **CHECK constraints zamiast ENUM:** Wartości kategoryczne jako TEXT z CHECK (np. origin, status, rating)
  - Łatwiejsze migracje: dodanie nowej wartości to ALTER TABLE bez przebudowy
  - Lepsze error messages: bardziej czytelne komunikaty błędów
  - Kompatybilność: łatwiejszy eksport/import między środowiskami

- **bigint dla token_usage:** Przygotowanie na duże wartości
  - 500k tokenów/dzień * 365 dni = 182.5M tokenów/rok
  - bigint mieści do 9,223,372,036,854,775,807 (9.2 quintillion) - wystarczy na wiele lat

- **numeric(5,2) dla ease_factor:** Precyzja dla wartości SRS
  - Format: XX.XX (np. 2.50, 1.30, 3.00)
  - Zakres: 1.00 do 999.99 (z CHECK >= 1.0)
  - Precyzja: lepsze od FLOAT dla obliczeń algorytmicznych

- **jsonb dla properties_json:** Wydajniejsze niż json
  - Indeksowanie: możliwość GIN index
  - Operatory: bogate możliwości zapytań (-> ->> @> ? itp.)
  - Storage: binarny format, szybsze przetwarzanie

### 6.2 Soft-delete

- **Powód:** Zachowanie integralności danych i historii
  - `review_logs` ma FK RESTRICT do `cards` - nie można fizycznie usunąć fiszki z historią przeglądów
  - Audyt: możliwość analizy usuniętych fiszek (co użytkownicy usuwają, dlaczego)
  - Recovery: teoretyczna możliwość przywrócenia przez admina (choć trigger to blokuje dla user-facing operacji)

- **Implementacja:** Kolumna `deleted_at` + indeksy częściowe
  - `deleted_at IS NULL` = fiszka aktywna
  - `deleted_at IS NOT NULL` = fiszka usunięta (timestamp usunięcia)
  - Indeksy częściowe `WHERE deleted_at IS NULL` - tylko aktywne fiszki, mniejsze i szybsze

- **Polityki RLS:** Domyślnie filtrują `deleted_at IS NULL`
  - Authenticated users: nie widzą swoich soft-deleted fiszek
  - Service role: widzi wszystko (audyt, analiza, potencjalne bulk operations)

- **Trigger walidacji:** Uniemożliwia przywracanie i równoczesną edycję podczas delete
  - Bezpieczeństwo: soft-delete to atomowa operacja
  - Spójność: jeśli ktoś chce "przywrócić", to musi utworzyć nową fiszkę

- **Alternatywa dla przyszłości:** Jeśli soft-deleted fiszek będzie bardzo dużo, można rozważyć przenoszenie do osobnej tabeli `cards_deleted` (partition by deleted_at)

### 6.3 Paginacja

- **Keyset pagination:** Preferowana przez indeks `idx_cards_user_date_active`
  - Sortowanie: `COALESCE(accepted_at, created_at) DESC, id DESC`
  - Stabilność: nowe/usunięte rekordy między stronami nie psują paginacji (w przeciwieństwie do OFFSET)
  - Wydajność: O(log n) dla każdej strony vs O(n) dla OFFSET przy dużych offsetach
  - Deep pagination: brak degradacji przy przechodzeniu do późnych stron

- **Implementacja frontend:**
  - Pierwsza strona: `WHERE deleted_at IS NULL AND user_id = $1 ORDER BY ... LIMIT 20`
  - Kolejne strony: `WHERE deleted_at IS NULL AND user_id = $1 AND (date, id) < ($last_date, $last_id) ORDER BY ... LIMIT 20`
  - `last_date` = COALESCE(accepted_at, created_at) z ostatniego rekordu poprzedniej strony
  - `last_id` = id z ostatniego rekordu poprzedniej strony (tie-breaker dla identycznych dat)

- **Alternative:** Cursor-based pagination (base64 encoded cursor z date+id) - bardziej user-friendly URLs

### 6.4 Bezpieczeństwo

- **RLS wszędzie:** Wszystkie tabele aplikacyjne mają włączony RLS i polityki per user
  - Ochrona: nawet jeśli błąd w aplikacji/API, baza nie zwróci cudzych danych
  - Defense in depth: RLS jako ostatnia linia obrony

- **Service role:** Osobne polityki z pełnym dostępem dla operacji systemowych
  - Agregacje: statystyki cross-user
  - Czyszczenie: retencja analytics_events
  - Migracje: bulk operations
  - Monitoring: health checks

- **Złożony FK w review_logs:** `(card_id, user_id)` → `cards(id, user_id)` z RESTRICT
  - Wymusza: zgodność user_id między review_log a card
  - Zapobiega: ocenianiu cudzych fiszek nawet przy błędzie w RLS/aplikacji
  - Bonus: wymusza soft-delete (RESTRICT blokuje fizyczne DELETE fiszek z historią)

- **ON DELETE RESTRICT:** Świadomy wybór dla review_logs
  - Wymusza: soft-delete jako jedyną drogę usunięcia fiszki z historią
  - Chroni: historyczne dane przed przypadkowym/złośliwym usunięciem

- **Prepared statements:** Zalecane dla wszystkich zapytań (ochrona przed SQL injection)

### 6.5 Wydajność i skalowalność

- **Indeksy częściowe:** Tylko dla aktywnych rekordów (`WHERE deleted_at IS NULL`)
  - Mniejsze: soft-deleted fiszki nie zajmują miejsca w indeksach
  - Szybsze: mniej danych do przeszukania
  - Selective: wysoka selektywność indeksów (blisko 100% aktywnych)

- **Indeksy złożone:** Dopasowane do najczęstszych query patterns
  - `user_id` zawsze pierwszy - umożliwia index-only scans per user
  - Sortowanie w indeksie - unikanie dodatkowego sort step
  - Covering indexes (przyszłość): można rozważyć INCLUDE dla często pobieranych kolumn

- **GIN dla JSONB:** Opcjonalny indeks dla `properties_json`
  - Dodać tylko jeśli będzie rzeczywista potrzeba filtrowania/wyszukiwania
  - Koszt: większy indeks, wolniejsze INSERT/UPDATE
  - Benefit: szybkie zapytania z warunkami JSONB (@>, ?, ->>)

- **Partycjonowanie (przyszłość):** Kandydaci przy dużym wzroście
  - `analytics_events` - partition by occurred_at (monthly/quarterly)
  - `review_logs` - partition by reviewed_at (monthly/quarterly)
  - Benefit: szybsze queries (partition pruning), łatwiejsze archiwizowanie starych danych

- **Vacuum i analyze:** Automatyczne przez Supabase, ale monitorować table bloat

- **Connection pooling:** Supabase Pooler (PgBouncer) dla serverless/edge functions

### 6.6 Zgodność z wymaganiami PRD

- ✅ **Prywatność użytkowników:** RLS + FK do auth.users z ON DELETE CASCADE
  - Każdy użytkownik widzi tylko swoje dane
  - Usunięcie konta usuwa wszystkie dane użytkownika

- ✅ **Walidacja limitów:** CHECK constraints dla długości tekstu
  - front_text: 1-200 znaków
  - back_text: 1-500 znaków
  - Walidacja na poziomie bazy (defense in depth)

- ✅ **Origin tracking:** Pole `origin` z walidacją spójności pól AI vs manual
  - CHECK constraint wymusza: origin='ai' ⟺ (source_language, generation_request_id, accepted_at) NOT NULL
  - CHECK constraint wymusza: origin='manual' ⟺ (source_language, generation_request_id, accepted_at) NULL

- ✅ **Telemetria generacji:** Tabela `generation_requests` z pełnymi metrykami
  - Status: success/partial/cancelled/error
  - Timing: started_at, computation_time_ms
  - Liczniki: generated_count, accepted_unedited_count, accepted_edited_count

- ✅ **Limity tokenów:** Tabela `token_usage` z UPSERT per (user_id, date_utc)
  - Composite PK umożliwia UPSERT bez konfliktów
  - bigint dla dużych wartości (500k/dzień * 365 dni)
  - Reset dzienny (nowy rekord per data UTC)

- ✅ **Analytics:** Tabela `analytics_events` z retencją 90 dni
  - Zdarzenia: card_accepted, card_rejected
  - Retencja: funkcja cleanup_old_analytics_events()
  - Powiązania: card_id, generation_request_id (z SET NULL dla zachowania zdarzeń)

- ✅ **SRS ready:** `review_logs` z polami before/after (NULL w MVP)
  - interval_days_before/after: gotowe na integrację z biblioteką SRS
  - ease_before/after: gotowe na tracking współczynnika łatwości
  - Struktura umożliwia przyszłą integrację bez migracji schematu

- ✅ **Soft-delete:** Implementacja dla `cards` z pełną walidacją
  - Kolumna deleted_at + indeksy częściowe + RLS + trigger
  - Ochrona integralności z review_logs (FK RESTRICT)

- ✅ **Brak wymuszania duplikatów:** Użytkownik może mieć identyczne fiszki
  - Brak UNIQUE constraint na (user_id, front_text, back_text)
  - Use case: ta sama fiszka w różnych kontekstach/zestawach

### 6.7 Nierozwiązane kwestie (poza MVP)

1. **Model SRS:** Docelowa struktura `srs_states` i algorytm aktualizacji
   - Który algorytm? FSRS (nowoczesny), SM-2 (klasyczny), Anki (modyfikacja SM-2)?
   - Gdzie logika algorytmu? Backend (preferowane) czy baza (stored procedures)?
   - Jak aktualizować? Przy każdym review atomowo (transaction)?
   - Migracja danych: jak zainicjować srs_states dla istniejących fiszek?

2. **Słownik modeli:** Czy `generation_requests.model` powinien mieć FK do tabeli słownikowej?
   - Pros: kontrola wartości, łatwiejsze raportowanie, możliwość metadanych (cost per token)
   - Cons: sztywność, migracje przy dodawaniu nowych modeli
   - Decyzja: najprawdopodobniej TEXT z CHECK lub bez constraintu (walidacja w aplikacji)

3. **Definicja metryk:** Dokładne reguły zliczania w generation_requests
   - `generated_count`: przed czy po deduplikacji? (decyzja: PO deduplikacji, max 10)
   - `accepted_edited_count` vs `accepted_unedited_count`: co to znaczy "edited"?
     - Propozycja: porównanie front_text/back_text przy akceptacji z oryginalnie wygenerowanymi
     - Gdzie trzymać oryginał? Nowa tabela `card_candidates`? W properties_json analytics_events?

4. **Kontrakt properties_json:** Jakie klucze, typy, limity rozmiaru?
   - Potrzebne dla dokumentacji API i walidacji
   - Przykłady: { "original_front": "...", "original_back": "...", "edit_distance": 5 }
   - Limit rozmiaru: 10KB? Walidacja przez CHECK octet_length(properties_json::text) <= 10240?

5. **PII w analytics:** Czy `properties_json` może zawierać dane osobowe?
   - Jeśli NIE: potrzebna walidacja/sanityzacja przed zapisem
   - Jeśli TAK: trzeba uwzględnić w privacy policy i GDPR compliance
   - Retencja 90 dni może być problemem z GDPR jeśli są PII (GDPR right to erasure)

6. **Harmonogram retencji:** Czy 2:00 UTC codziennie jest OK?
   - Monitoring: jak sprawdzać czy zadanie się wykonało? Logs? Metryka w bazie?
   - Performance: czy DELETE na dużej liczbie rekordów (miliony) nie będzie blokować?
   - Partycjonowanie: może lepiej DROP PARTITION niż DELETE dla starych danych?

### 6.8 Migracje i deployment

**Kolejność tworzenia (ważne dla zależności FK):**

1. **Tabele bez FK do innych tabel aplikacyjnych:**
   - `generation_requests` (tylko FK do auth.users)
   - `token_usage` (tylko FK do auth.users)

2. **Tabele z FK do tabel aplikacyjnych:**
   - `cards` (FK do generation_requests - opcjonalnie)
   - Unique constraint: `cards(id, user_id)` - wymagane przed review_logs

3. **Tabele zależne:**
   - `review_logs` (złożony FK do cards)
   - `analytics_events` (FK do cards i generation_requests)

4. **Indeksy:** Wszystkie indeksy dla wszystkich tabel

5. **Funkcje:** Funkcje PRZED triggerami (zależność)
   - `update_updated_at_column()`
   - `validate_card_soft_delete()`
   - `cleanup_old_analytics_events()`

6. **Triggery:** Po funkcjach
   - `cards_updated_at_trigger`
   - `cards_soft_delete_trigger`

7. **Polityki RLS:** Na końcu (wymaga istniejących tabel)
   - Włączenie RLS na wszystkich tabelach
   - Utworzenie polityk per tabela

**Rollback strategy:**

- Każda migracja musi mieć odpowiedni DOWN migration script
- Testowanie DOWN przed merge do main
- Kolejność rollback: odwrotna do tworzenia (najpierw RLS, triggery, funkcje, indeksy, tabele zależne, tabele bazowe)

**Testy przed deploymentem:**

- Testy RLS: sprawdzenie że user A nie widzi danych user B
- Testy FK: sprawdzenie cascades i restricts
- Testy soft-delete: walidacja przez trigger
- Testy indeksów: EXPLAIN ANALYZE dla kluczowych query patterns
- Load testing: performance przy 10k, 100k, 1M rekordów

**Seed data (development):**

- Przykładowe fiszki: AI i manual, różne języki
- Testowi użytkownicy: z różnymi scenariuszami (nowy user, power user, user z soft-deleted cards)
- Historia przeglądów: różne rating combinations
- Zdarzenia analityczne: reprezentatywne event_name
- Token usage: różne poziomy wykorzystania (blisko limitu, poniżej)

### 6.9 Monitoring i observability

**Zalecane metryki:**

- **Rozmiar tabel i indeksów:** Tracking wzrostu, alerty przy niespodziewanym wzroście
  - Query: `SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) FROM pg_tables WHERE schemaname = 'public'`

- **Query performance:** pg_stat_statements
  - Top 10 slowest queries
  - Top 10 most frequent queries
  - Queries with highest total time

- **RLS policy hit rate:** Monitoring czy polityki są używane
  - Alerty jeśli query omija RLS (potencjalne luki bezpieczeństwa)

- **Token usage per user:** Alerty przy zbliżaniu się do limitu
  - Dashboard: użytkownicy > 80% limitu dziennego
  - Alert: użytkownik przekroczył limit (powinno być blokowane przez aplikację, ale monitoring defense in depth)

- **Liczba soft-deleted vs active cards:** Ratio monitoring
  - Jeśli > 20% soft-deleted: może być potrzebne archiwizowanie
  - Jeśli wzrost soft-deleted > 10%/tydzień: może wskazywać na problem z UX/produktem

- **Częstotliwość retencji analytics_events:** Monitoring cleanup_old_analytics_events
  - Liczba usuniętych rekordów per run
  - Czas wykonania (jeśli > 5s: rozważyć partycjonowanie)
  - Last run timestamp (alert jeśli > 25h - zadanie się nie wykonało)

**Alerty:**

- **Przekroczenie założonego czasu zapytań:**
  - Lista fiszek: > 100ms (p95)
  - Pojedyncza fiszka: > 10ms (p95)
  - Generacja (suma API + DB): > 10s (p95) - zgodnie z PRD

- **Błędy FK constraints:** Nieoczekiwane próby naruszenia integralności
  - Review_logs z nieistniejącym card_id
  - Card z nieistniejącym generation_request_id (nie powinno się zdarzyć)

- **Nieudane operacje RLS:** Potencjalne próby naruszenia bezpieczeństwa
  - Logged przez Supabase jako failed_policy checks
  - Alert jeśli > 10 failed checks / user / hour

- **Deadlocks:** Monitoring pg_stat_database.deadlocks
  - Jeśli > 0: analiza conflicting transactions i optymalizacja kolejności operacji

- **Connection pool exhaustion:** Z Supabase Pooler metrics
  - Alert jeśli available connections < 10% pool size

### 6.10 Integracja z Next.js i Supabase

- **Supabase Client:** Automatyczna obsługa RLS przez `supabase-js` SDK
  - Client-side: `createClientComponentClient()` z user auth context
  - Server-side: `createServerComponentClient()` lub `createRouteHandlerClient()`
  - Service role: `createClient(url, serviceRoleKey)` dla Edge Functions / API routes

- **Auth:** Wykorzystanie wbudowanego `auth.users` i `auth.uid()` w RLS
  - User context automatycznie przekazywany przez Supabase client
  - Middleware Next.js: refresh session, redirect jeśli unauthorized
  - Protected routes: layout.tsx z auth check

- **Real-time (opcjonalnie):** Można włączyć dla `cards` jeśli będzie potrzeba live updates
  - Use case: multi-device sync (user edytuje na komputerze, widzi update na tablecie)
  - Implementacja: `supabase.channel().on('postgres_changes', ...)` w React
  - Performance: filtrować tylko own cards (`user_id = auth.uid()`)

- **Postgrest API:** Automatyczne RESTful endpoints dla wszystkich tabel
  - GET, POST, PATCH, DELETE automatycznie respektują RLS
  - Filtering: `?user_id=eq.xxx&deleted_at=is.null`
  - Ordering: `?order=created_at.desc`
  - Pagination: `?limit=20&offset=0` lub keyset z `?and=(created_at.lt.xxx,id.lt.yyy)`

- **Edge Functions:** Service role dla operacji systemowych
  - Generacja AI: `/functions/generate-cards` z service role client (pomija RLS)
  - Czyszczenie: `/functions/cleanup-analytics` scheduled daily
  - Webhooks: Stripe, zewnętrzne integracje

- **TypeScript types:** Auto-generated z `supabase gen types typescript`
  - Import: `import type { Database } from '@/types/supabase'`
  - Użycie: `const { data } = await supabase.from('cards').select<Database['public']['Tables']['cards']['Row']>()`

- **Row Level Security testing:** Supabase Studio RLS validator lub testy integracyjne
  - Test: user A nie widzi cards user B
  - Test: authenticated może INSERT z własnym user_id
  - Test: authenticated nie może UPDATE cudzych cards

---

**Status dokumentu:** Gotowy do implementacji migracji  
**Wersja:** 2.0  
**Data:** 2025-11-25  
**Autor:** AI Architect + Piotrek

**Changelog:**
- v2.0: Przekształcenie bloków SQL na opis tekstowy (punkty 1, 3, 4, 5)
- v1.0: Pierwsza wersja z kodem SQL
