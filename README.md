# LifeSpan

Created May 2025, now migrating to GitHub and polishing it up.

An iOS app that shows how long animals live, with an animal of the day and a searchable catalog of about 1,450 animals. A Python pipeline builds the dataset and a SwiftUI app reads it from Supabase.

## How it works

```
API Ninjas ─┐
Pexels     ─┼─> Python ETL ──upsert──> Supabase (Postgres) ──REST──> SwiftUI app + widgets
Wikipedia  ─┘
```

### Data pipeline (`animalScrape.py`, `secondScrape.py`)

- Builds a seed list of animal names from the API Ninjas animals API.
- For each animal, pulls facts (habitat, diet, lifespan, taxonomy) from API Ninjas, a photo from Pexels, and a description from Wikipedia.
- Wikipedia lookups have fallbacks: if the direct title isn't found, retry with `"<name> animal"`. If the title is ambiguous, pick the disambiguation option that looks like an animal (animal, mammal, fish, bird).
- Rows are written to Supabase with an upsert on `name`, so re-running never creates duplicates.
- `secondScrape.py` is the gap-filler. It pages through the existing rows into a set, diffs that against the seed list, and only fetches the animals that are missing.
- Calls are rate limited with sleeps to stay inside the free API tiers.

### Database

One `animals` table in Supabase (Postgres): `id`, `name`, `habitat`, `diet`, `image_url`, `description`, `json_data` (the raw API payload as JSONB), `created_at`.

### App (`LifeSpan/`)

- **Today:** an animal of the day. Everyone gets the same animal on a given date, and a shuffle button picks a random one.
- **Browse:** a searchable, paginated list of every animal.
- **Detail:** lifespan compared with a human lifespan, plus habitat, diet, taxonomy and a description.
- **Widgets (`LifeSpanWidget/`):** home screen and lock screen widgets for the animal of the day.

The app talks to Supabase's REST endpoint with `URLSession` and has no third-party dependencies.

## Setup

### Python scripts

```sh
pip install requests supabase wikipedia
cp .env.example .env     # fill in your keys
export $(grep -v '^#' .env | xargs)
python3 animalScrape.py  # initial load
python3 secondScrape.py  # fill in anything missing
```

The scripts use the Supabase **service_role** key, so keep it out of the app and out of git.

### iOS app

1. Copy `LifeSpan/Secrets.swift.example` to `LifeSpan/Secrets.swift` (it's gitignored).
2. Fill in your project URL and the **anon** key from Supabase > Project Settings > API.
3. In Supabase, add a `SELECT` Row Level Security policy on `animals` for the `anon` role.
4. Open `LifeSpan.xcodeproj` and run the `LifeSpan` scheme.

To add the widget, create a Widget Extension target named `LifeSpanWidget`, use the files in `LifeSpanWidget/`, and add `Animal.swift`, `AnimalService.swift` and `Secrets.swift` to that target.

## Known issues

- Some descriptions and attributes in the data are wrong or badly formatted.
- Pexels photos are a keyword match, so obscure animals can get unrelated pictures.

## Tech

Python, Supabase (Postgres, PostgREST), SwiftUI, WidgetKit, API Ninjas, Pexels, Wikipedia.
