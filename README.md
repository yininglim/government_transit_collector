# 🚌 Government Transit Collector

A Flutter-based smart public transportation application designed for MyBAS services in Johor Bahru, Malaysia. The system supports passengers in planning and tracking bus journeys while providing administrators with operational analysis and AI-assisted recommendations for improving bus services.

---

## 📖 Project Overview

Government Transit Collector is a mobile application developed to support the use and management of public bus transportation in Johor Bahru.

The system integrates GTFS Static and GTFS Realtime data to provide journey recommendations, live bus tracking, and historical bus operation analysis. Passenger feedback and collected operational data are also used to support administrators in understanding route performance and identifying potential service improvements.

The application consists of three main modules:

1. **Departure Recommendation**
2. **Real-time Journey Tracker**
3. **AI Smart Route Recommendation**

Together, these modules connect passenger journey services with operational analysis, allowing collected transportation data and passenger feedback to support data-driven bus service improvement.

---

# ✨ Features

## 🧭 Departure Recommendation

The Departure Recommendation module helps passengers identify suitable bus journeys based on their selected departure and destination stops.

### Main Features

- Search departure and destination stops
- Direct journey recommendation
- Transfer journey recommendation
- Realtime trip availability
- Bus route and journey information
- Start journey tracking
- Passenger feedback and issue reporting

Passengers can report issues experienced while using a particular route. The submitted feedback provides additional information that can be considered together with operational analysis when evaluating bus services.

---

## 📍 Real-time Journey Tracker

The Real-time Journey Tracker allows passengers to monitor MyBAS bus movements and track selected journeys using GTFS Realtime vehicle-position data.

### Main Features

- Live bus locations
- Route-based vehicle filtering
- Selected journey tracking
- Current journey progress
- Next-stop information
- Estimated arrival time (ETA)
- Passenger location
- Interactive journey route map
- Historical realtime vehicle-position collection

Realtime vehicle observations are collected periodically and stored in Supabase. These historical records provide the operational data required for administrative route analysis.

---

## 🤖 AI Smart Route Recommendation

The AI Smart Route Recommendation module supports administrators in analysing historical bus operations and passenger feedback to assist with service improvement decisions.

The module combines several types of analysis before producing overall recommendations.

### 📊 Route Performance Analysis

Evaluates the historical performance of individual bus routes using collected realtime vehicle-position data.

- Average travel time
- Delay frequency
- Schedule adherence
- Historical trip coverage
- Complete and partial trip analysis
- Route-specific analysis
- Multiple date-range selection

### ⏰ Peak Operation Analysis

Analyses historical bus activity to identify periods with higher levels of observed bus operations.

- Data-derived peak operational periods
- Average active trips
- Busiest observed route
- Observed service window
- Daily operational activity
- Route-specific analysis
- Today, 7 Days, and Custom date ranges

Peak periods are derived from collected operational data rather than using predefined peak-hour values.

> **Note:** Peak Operation Analysis represents observed bus operational activity and does not represent passenger ridership or passenger demand.

### 💡 AI Recommendation

The AI Recommendation component uses available operational analysis together with passenger feedback to generate recommendations that support administrators in identifying potential route and service improvements.

The recommendation process can consider information from:

- Route performance analysis
- Peak operation analysis
- Historical bus operation data
- Passenger feedback and reported route issues

The generated recommendations are intended to support administrative decision-making rather than automatically modify bus routes or schedules.

---

# 🛠 Tech Stack

| Technology | Usage |
| --- | --- |
| Flutter | Mobile Application Framework |
| Dart | Programming Language |
| Supabase | Backend Platform |
| PostgreSQL | Database |
| Supabase Auth | Authentication and Role Management |
| GTFS Static | Bus Route, Stop, Trip, and Schedule Data |
| GTFS Realtime | Live Vehicle Position Data |
| OpenStreetMap | Map and Route Display |
| Git & GitHub | Version Control and Collaboration |
| Android Studio | Development Environment |

---

# 📂 Project Structure

```text
government_transit_collector/
│
├── lib/
│   ├── app/
│   ├── core/
│   └── features/
│       ├── authentication/
│       ├── departure_recommendation/
│       ├── realtime_vehicle/
│       ├── route_performance/
│       ├── peak_operation/
│       └── admin_home/
│
├── scripts/
├── supabase/
├── test/
├── .env.example
├── pubspec.yaml
└── README.md
```

---

# ⚙️ Installation

## 1. Clone Repository

Clone the repository using Git:

```bash
git clone <repository-url>
```

Alternatively, clone the repository using GitHub Desktop.

---

## 2. Enter Project

```bash
cd government_transit_collector
```

---

## 3. Install Flutter Dependencies

Make sure Flutter is installed and configured correctly.

Then run:

```bash
flutter pub get
```

---

## 4. Configure Environment

Create a `.env` file in the project root and configure the Supabase connection.

```env
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
```

> **Note:** The `.env` file and Supabase secret keys must not be committed to GitHub. Each team member should configure the required environment variables locally.

---

## 5. Run Application

Connect an Android device or start an Android emulator.

Then run:

```bash
flutter run
```

The application can also be launched directly through Android Studio.

---

# 📡 Historical Realtime Data Collection

Historical MyBAS vehicle-position data is collected to support Route Performance Analysis and Peak Operation Analysis.

To start continuous historical data collection:

```bash
dart run scripts/realtime_history_collector.dart --interval-minutes=2
```

The collector retrieves GTFS Realtime vehicle positions approximately every two minutes and stores valid historical observations in the Supabase `vehicle_positions` table.

The computer running the collector should remain awake and connected to the internet during data collection.

Use `Ctrl+C` to stop the collector.

> **Important:** The Supabase service-role key required by the historical collector must only be configured locally and must never be committed to GitHub.

---

# 🔄 System Data Flow

The three main modules work together by connecting passenger services, realtime transportation data, operational analysis, and administrative recommendations.

```text
              GTFS Static + GTFS Realtime
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
     Departure Recommendation   Real-time Journey
              │                     Tracker
              │                       │
              │                       ▼
              │              Historical Bus Data
              │                       │
              ▼                       ▼
       Passenger Feedback      Operational Analysis
              │                ┌──────┴───────┐
              │                ▼              ▼
              │          Route Performance   Peak Operation
              │              Analysis          Analysis
              │                │              │
              └────────────────┴──────┬───────┘
                                      ▼
                              AI Recommendation
                                      │
                                      ▼
                            Service Improvement
                               Decision Support
```

---

# 🗄 Database

The application uses **Supabase PostgreSQL** as its central database.

The database manages information including:

- User profiles and roles
- GTFS agencies
- Bus stops
- Bus routes
- Bus trips and schedules
- Passenger journey-related data
- Passenger feedback and issue reports
- Realtime and historical vehicle positions
- Data required for administrative analysis

Row Level Security (RLS) is used to control database access according to user roles and application requirements.

Historical vehicle-position observations are stored in `vehicle_positions` and are used by the Route Performance and Peak Operation analyses.

Database schema changes should be managed through the project's migration files rather than manually modifying the production database schema.

---

# 👨‍💻 Team Workflow

This project uses a personal branch workflow for collaborative development.

Each team member develops assigned features on their own branch before completed work is integrated into the main project.

## Create Personal Branch

```bash
git checkout -b yourname-dev
git push -u origin yourname-dev
```

Example:

```text
jingting-dev
member2-dev
member3-dev
```

---

## Update Local Repository

Before starting new development work, update the local `master` branch:

```bash
git checkout master
git pull origin master
```

Then switch back to the personal branch:

```bash
git checkout yourname-dev
git merge master
```

Resolve any conflicts before continuing development.

---

## Test Changes

Before committing changes, run:

```bash
flutter analyze
flutter test
```

---

## Commit Changes

```bash
git add .
git commit -m "Describe your changes"
```

---

## Push Branch

```bash
git push origin yourname-dev
```

---

## Merge Completed Work

After a feature has been completed and tested:

1. Push the latest personal branch.
2. Review the implemented changes.
3. Resolve any integration conflicts.
4. Merge the completed work into the main branch.
5. Other team members pull the updated main branch before continuing related development.

---

# 🔐 Security Notes

- Do not commit `.env` files.
- Do not commit the Supabase service-role key.
- Do not expose privileged database credentials in Flutter client code.
- Use the existing authentication and role-based authorization mechanisms.
- Database schema changes should be performed through migration files.
- Avoid destructive changes to the shared Supabase database.
- Historical realtime data is stored in Supabase and is not stored through Git commits.

---

# 📄 License

This project is developed for academic purposes as part of a Software Engineering coursework project.
