# Government Transit Collector

## Project Overview

Government Transit Collector is a smart public transportation management system developed using Flutter and Supabase. The system helps passengers plan their journeys while assisting transport authorities in analysing bus operations and improving public transport services in Johor.

---

# Technology Stack

- Flutter
- Dart
- Supabase
- PostgreSQL
- Android Studio
- GitHub

---

# Current Progress

- ✅ Flutter project setup
- ✅ GitHub repository
- ✅ Supabase integration
- ✅ Database schema
- ✅ Email/password authentication
- ✅ Passenger & Admin role routing

---

# Project Setup

## 1. Clone the Repository

```bash
git clone <repository-url>
```

or use GitHub Desktop.

---

## 2. Open the Project

Open the project folder in Android Studio.

---

## 3. Pull the Latest Source Code

```bash
git checkout master
git pull origin master
```

---

## 4. Create Your Own Branch

Each team member must develop on their own branch.

Example:

```bash
git checkout -b yourname-dev
git push -u origin yourname-dev
```

Examples:

- jingting-dev
- member2-dev
- member3-dev

---

## 5. Configure Environment Variables

Create a `.env` file in the project root.

Example:

```env
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_ANON_KEY
```

> Do **not** commit `.env` to GitHub.

---

## 6. Install Dependencies

```bash
flutter pub get
```

---

## 7. Run the Project

```bash
flutter run
```

or run directly from Android Studio.

---

## 8. When pubspec.yaml Changes

Run:

```bash
flutter pub get
```

---

## 9. Before Starting Development

Update your local repository.

```bash
git checkout master
git pull origin master
```

Switch back to your own branch.

```bash
git checkout yourname-dev
git merge master
```

Resolve conflicts if necessary.

---

## 10. Before Committing

Run:

```bash
flutter analyze
flutter test
```

Commit:

```bash
git add .
git commit -m "Your commit message"
```

Push:

```bash
git push origin yourname-dev
```

---

## 11. Merge Process

After a feature has been completed and tested:

1. Push your branch.
2. Notify the repository owner.
3. The repository owner will merge the branch into `master`.

---

## Important Notes

- Never commit `.env`
- Never commit downloaded GTFS ZIP files
- Never commit downloaded GTFS Realtime files
- Always develop on your own branch
- Pull the latest `master` before starting new work
- Test before committing
- Use meaningful commit messages

---

# Next Development Tasks

- GTFS Static Import
- Departure Recommendation
- Real-time Journey Tracker
- AI Smart Route Recommendation
