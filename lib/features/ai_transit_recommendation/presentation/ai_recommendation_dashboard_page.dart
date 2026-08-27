import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/bus_frequency_recommendation_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/route_bus_stop_recommendation_page.dart';

class AiRecommendationDashboardPage extends StatelessWidget {
  const AiRecommendationDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Recommendation Dashboard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'AI Transit Recommendation',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Select a recommendation area to continue.'),
            const SizedBox(height: 32),
            _RecommendationSection(
              icon: Icons.schedule,
              title: 'Bus Frequency Recommendation',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BusFrequencyRecommendationPage(),
                ),
              ),
            ),
            _RecommendationSection(
              icon: Icons.alt_route,
              title: 'Route & Bus Stop Recommendation',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RouteBusStopRecommendationPage(),
                ),
              ),
            ),
            _RecommendationSection(
              icon: Icons.request_quote_outlined,
              title: 'Cost Estimation Report',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CostEstimationReportPage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationSection extends StatelessWidget {
  const _RecommendationSection({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
