import 'dart:math';

/// OpenSkill（Weng-Lin Plackett-Luce）の Dart 実装。
/// openskill.js (MIT) を参考にしています。
class OpenSkillRating {
  final double mu;
  final double sigma;

  const OpenSkillRating({required this.mu, required this.sigma});

  OpenSkillRating copyWith({double? mu, double? sigma}) =>
      OpenSkillRating(mu: mu ?? this.mu, sigma: sigma ?? this.sigma);
}

class OpenSkillConstants {
  static const double defaultMu = 25.0;
  static const double defaultSigma = defaultMu / 3.0;
  static const double beta = defaultMu / 6.0;
  static const double tau = defaultMu / 300.0;
  static const double kappa = 0.0001;
  static const double z = 3.0;
  static const int displayRatingOffset = 1500;

  static OpenSkillRating defaultRating() =>
      const OpenSkillRating(mu: defaultMu, sigma: defaultSigma);
}

class OpenSkill {
  static double ordinal(OpenSkillRating rating) =>
      rating.mu - OpenSkillConstants.z * rating.sigma;

  static int displayRating(OpenSkillRating rating) =>
      (ordinal(rating) + OpenSkillConstants.displayRatingOffset).round();

  /// 旧 ELO のみ保存されているプレイヤーを OpenSkill パラメータへ移行
  static OpenSkillRating fromLegacyRating(int legacyRating) {
    final ordinalValue = legacyRating - OpenSkillConstants.displayRatingOffset;
    return OpenSkillRating(
      mu: ordinalValue + OpenSkillConstants.z * OpenSkillConstants.defaultSigma,
      sigma: OpenSkillConstants.defaultSigma,
    );
  }

  static OpenSkillRating parseStored({
    required dynamic muValue,
    required dynamic sigmaValue,
    required dynamic ratingValue,
  }) {
    if (muValue is num && sigmaValue is num) {
      return OpenSkillRating(mu: muValue.toDouble(), sigma: sigmaValue.toDouble());
    }
    if (ratingValue is num) {
      return fromLegacyRating(ratingValue.round());
    }
    return OpenSkillConstants.defaultRating();
  }

  /// 各チーム 1 プレイヤーの対戦結果から μ・σ を更新する
  static List<List<OpenSkillRating>> rate(
    List<List<OpenSkillRating>> teams,
    List<double> ranks, {
    double tau = OpenSkillConstants.tau,
  }) {
    if (teams.length < 2) return teams;
    if (ranks.length != teams.length) {
      throw ArgumentError('ranks length must match teams length');
    }

    final tauSquared = tau * tau;
    final processed = teams
        .map(
          (team) => team
              .map(
                (p) => p.copyWith(
                  sigma: sqrt(p.sigma * p.sigma + tauSquared),
                ),
              )
              .toList(),
        )
        .toList();

    final indexed = List.generate(
      processed.length,
      (i) => (rank: ranks[i], team: processed[i], index: i),
    )..sort((a, b) => a.rank.compareTo(b.rank));

    final sortedTeams = indexed.map((e) => e.team).toList();
    final sortedRanks = indexed.map((e) => e.rank).toList()..sort();
    final rated = _plackettLuce(sortedTeams, sortedRanks);

    final result = List<List<OpenSkillRating>>.from(processed);
    for (var i = 0; i < indexed.length; i++) {
      result[indexed[i].index] = rated[i];
    }
    return result;
  }

  static List<List<OpenSkillRating>> _plackettLuce(
    List<List<OpenSkillRating>> game,
    List<double> rankInput,
  ) {
    final betaSq = OpenSkillConstants.beta * OpenSkillConstants.beta;
    final teamRatings = _teamRatings(game, rankInput);
    final c = _utilC(teamRatings, betaSq);
    final sumQ = _utilSumQ(teamRatings, c);
    final a = _utilA(teamRatings);

    return List.generate(teamRatings.length, (i) {
      final iTeam = teamRatings[i];
      final iMuOverCe = exp(iTeam.muSum / c);
      var omegaSum = 0.0;
      var deltaSum = 0.0;

      for (var q = 0; q < teamRatings.length; q++) {
        if (teamRatings[q].rank > iTeam.rank) continue;
        final quotient = iMuOverCe / sumQ[q];
        omegaSum += (i == q ? 1 - quotient : -quotient) / a[q];
        deltaSum += (quotient * (1 - quotient)) / a[q];
      }

      final gamma = sqrt(iTeam.sigmaSq) / c;
      final omega = omegaSum * (iTeam.sigmaSq / c);
      final delta = deltaSum * (iTeam.sigmaSq / (c * c)) * gamma;

      return iTeam.team.map((player) {
        final sigmaSq = player.sigma * player.sigma;
        final newMu = player.mu + (sigmaSq / iTeam.sigmaSq) * omega;
        final newSigma = player.sigma *
            sqrt(max(1 - (sigmaSq / iTeam.sigmaSq) * delta, OpenSkillConstants.kappa));
        return OpenSkillRating(mu: newMu, sigma: newSigma);
      }).toList();
    }).toList();
  }

  static List<_TeamRatingData> _teamRatings(
    List<List<OpenSkillRating>> game,
    List<double> rankInput,
  ) {
    final placementRanks = _placementRanks(rankInput);
    return List.generate(game.length, (i) {
      final team = game[i];
      var muSum = 0.0;
      var sigmaSq = 0.0;
      for (final player in team) {
        muSum += player.mu;
        sigmaSq += player.sigma * player.sigma;
      }
      return _TeamRatingData(
        muSum: muSum,
        sigmaSq: sigmaSq,
        team: team,
        rank: placementRanks[i],
      );
    });
  }

  static List<int> _placementRanks(List<double> rankInput) {
    final outRank = List<int>.filled(rankInput.length, 0);
    var s = 0;
    for (var j = 0; j < rankInput.length; j++) {
      if (j > 0 && rankInput[j - 1] < rankInput[j]) {
        s = j;
      }
      outRank[j] = s;
    }
    return outRank;
  }

  static double _utilC(List<_TeamRatingData> teamRatings, double betaSq) {
    var sum = 0.0;
    for (final team in teamRatings) {
      sum += team.sigmaSq + betaSq;
    }
    return sqrt(sum);
  }

  static List<double> _utilSumQ(List<_TeamRatingData> teamRatings, double c) {
    return teamRatings.map((qTeam) {
      var sum = 0.0;
      for (final iTeam in teamRatings) {
        if (iTeam.rank >= qTeam.rank) {
          sum += exp(iTeam.muSum / c);
        }
      }
      return sum;
    }).toList();
  }

  static List<int> _utilA(List<_TeamRatingData> teamRatings) {
    return teamRatings
        .map(
          (iTeam) => teamRatings.where((qTeam) => qTeam.rank == iTeam.rank).length,
        )
        .toList();
  }
}

class _TeamRatingData {
  final double muSum;
  final double sigmaSq;
  final List<OpenSkillRating> team;
  final int rank;

  const _TeamRatingData({
    required this.muSum,
    required this.sigmaSq,
    required this.team,
    required this.rank,
  });
}
