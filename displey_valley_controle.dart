import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mqtt_service.dart';
import 'valley_display_screen.dart';

// Модель для хранения данных Valley
class ValleyData {
  final String id;
  bool isOnline;
  bool isRunning;
  DateTime? startTime;
  Duration totalRunTime;
  String lastSessionInfo;

  ValleyData({
    required this.id,
    this.isOnline = false,
    this.isRunning = false,
    this.startTime,
    this.totalRunTime = Duration.zero,
    this.lastSessionInfo = '--:--',
  });
}

class ValleyControlScreen extends StatefulWidget {
  final MQTTService mqttService;

  const ValleyControlScreen({
    super.key,
    required this.mqttService,
  });

  @override
  State<ValleyControlScreen> createState() => _ValleyControlScreenState();
}

class _ValleyControlScreenState extends State<ValleyControlScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late List<Particle> particles;
  Timer? _particleTimer;
  Timer? _updateTimer;

  // Данные 5 Valley
  final List<ValleyData> _valleys = List.generate(
    5,
        (index) => ValleyData(id: 'VALLEY-${index + 1}'),
  );

  // Переменные для сохранения сессий (для уведомлений в будущем)
  final List<Map<String, dynamic>> _sessionHistory = [];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initParticles();
    _startParticleTimer();
    _startUpdateTimer();
    _subscribeToTopics();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _initParticles() {
    particles = List.generate(50, (_) => Particle());
  }

  void _startParticleTimer() {
    _particleTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (mounted) {
        setState(() {
          for (var particle in particles) {
            particle.update();
          }
        });
      }
    });
  }

  // Таймер для обновления времени работы
  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          for (var valley in _valleys) {
            if (valley.isRunning && valley.startTime != null) {
              
            }
          }
        });
      }
    });
  }

  void _subscribeToTopics() {
    // Подписка на статус онлайн/оффлайн для каждого Valley
    for (var valley in _valleys) {
      widget.mqttService.subscribe('valley/${valley.id}/status', (message) {
        setState(() {
          valley.isOnline = message == 'online';
        });
      });

      // Подписка на режим работы
      widget.mqttService.subscribe('valley/${valley.id}/mode', (message) {
        setState(() {
          final wasRunning = valley.isRunning;
          valley.isRunning = message == 'running';

          // Если только что запустилось
          if (!wasRunning && valley.isRunning) {
            valley.startTime = DateTime.now();
          }
          // Если только что остановилось
          else if (wasRunning && !valley.isRunning) {
            _saveSession(valley);
          }
        });
      });
    }
  }

  // Сохранение сессии в переменную (для будущих уведомлений)
  void _saveSession(ValleyData valley) {
    if (valley.startTime != null) {
      final endTime = DateTime.now();
      final duration = endTime.difference(valley.startTime!);
      valley.totalRunTime += duration;

      final sessionInfo = {
        'valleyId': valley.id,
        'startTime': valley.startTime!.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'duration': duration.inSeconds,
        'date': '${endTime.day}.${endTime.month}.${endTime.year}',
        'time': '${endTime.hour}:${endTime.minute.toString().padLeft(2, '0')}',
      };

      _sessionHistory.add(sessionInfo);
      valley.lastSessionInfo = '${sessionInfo['date']} ${sessionInfo['time']}';
      valley.startTime = null;

      // Лог для проверки
      print('Сессия сохранена: $sessionInfo');
      print('Всего сессий: ${_sessionHistory.length}');
    }
  }

  String _getCurrentRunTime(ValleyData valley) {
    if (!valley.isRunning || valley.startTime == null) {
      return valley.isRunning ? '00:00:00' : '--:--:--';
    }

    final duration = DateTime.now().difference(valley.startTime!);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _particleTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Фон
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.lerp(const Color(0xFF0D47A1), const Color(0xFF1976D2), _pulseAnimation.value)!,
                      const Color(0xFF1565C0),
                      Color.lerp(const Color(0xFF42A5F5), const Color(0xFF1565C0), _pulseAnimation.value)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          ),

          // Частицы
          CustomPaint(
            painter: ParticlePainter(particles),
            size: size,
          ),

          // Основной контент с CustomScrollView
          SafeArea(
            child: CustomScrollView(
              slivers: [
                // Статус сервера
                SliverToBoxAdapter(
                  child: _buildStatusBar(),
                ),

                // Отступ
                const SliverToBoxAdapter(
                  child: SizedBox(height: 16),
                ),

                // Кнопка назад и заголовок
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            child: Icon(
                              Icons.arrow_back_ios,
                              color: Colors.white.withOpacity(0.9),
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Управление Valley',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withOpacity(0.95),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Отступ
                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),

                SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _buildValleyCard(_valleys[index]),
                      );
                    },
                    childCount: _valleys.length,
                  ),
                ),

                // Нижний отступ для тени последнего элемента
                const SliverToBoxAdapter(
                  child: SizedBox(height: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: StreamBuilder<bool>(
        stream: widget.mqttService.connectionStream,
        initialData: widget.mqttService.isConnected,
        builder: (context, snapshot) {
          final connected = snapshot.data ?? false;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: connected
                    ? [Colors.green.shade600, Colors.green.shade400]
                    : [Colors.red.shade600, Colors.red.shade400],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (connected ? Colors.green : Colors.red).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    connected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? 'Подключено' : 'Нет подключения',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'MQTT Сервер',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    connected ? 'ON' : 'OFF',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildValleyCard(ValleyData valley) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 30,
            spreadRadius: -10,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 40,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.5),
            width: 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.9),
              Colors.white.withOpacity(0.8),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === КЛИКАБЕЛЬНАЯ ВЕРХНЯЯ ЧАСТЬ ===
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                // Здесь переход на экран деталей Valley
                print('Нажато: ${valley.id}');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ValleyDisplayScreen(
                      mqttService: widget.mqttService,
                      valleyId: valley.id, // Передаем ID нажатого Valley
                    ),
                  ),
                );
              },
              child: Container(
                color: Colors.transparent, 
                child: Column(
                  children: [
                    // ID и статус онлайн
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blue.shade600, Colors.cyan.shade500],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.water_drop,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              valley.id,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        // Индикатор онлайн/оффлайн
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: valley.isOnline
                                ? Colors.green.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: valley.isOnline
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.grey.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: valley.isOnline ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                valley.isOnline ? 'ONLINE' : 'OFFLINE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: valley.isOnline ? Colors.green : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                  ],
                ),
              ),
            ),
            // === КОНЕЦ КЛИКАБЕЛЬНОЙ ЧАСТИ ===

            const SizedBox(height: 16),

            // Режим работы
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    icon: valley.isRunning ? Icons.play_arrow : Icons.pause,
                    label: 'Режим',
                    value: valley.isRunning ? 'Запущена' : 'Остановлена',
                    color: valley.isRunning ? Colors.green : Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    icon: Icons.timer_outlined,
                    label: 'Время работы',
                    value: _getCurrentRunTime(valley),
                    color: Colors.blue,
                    isTimer: valley.isRunning,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Последняя сессия
            if (!valley.isRunning && valley.lastSessionInfo != '--:--')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history,
                      size: 16,
                      color: Colors.blue.shade400,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Последняя сессия: ${valley.lastSessionInfo}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isTimer = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: isTimer ? 20 : 16,
            fontWeight: FontWeight.bold,
            color: color,
            fontFeatures: isTimer ? [const FontFeature.tabularFigures()] : null,
          ),
        ),
      ],
    );
  }
}

// Классы частиц
class Particle {
  double x, y;
  double speedX, speedY;
  double size;
  double opacity;
  Color color;
  double life;
  double maxLife;

  Particle()
      : x = math.Random().nextDouble(),
        y = math.Random().nextDouble(),
        speedX = (math.Random().nextDouble() - 0.5) * 0.002,
        speedY = (math.Random().nextDouble() - 0.5) * 0.002,
        size = math.Random().nextDouble() * 2 + 1,
        opacity = math.Random().nextDouble() * 0.5 + 0.2,
        color = Colors.white,
        life = 0,
        maxLife = double.infinity;

  void update() {
    x += speedX;
    y += speedY;
    life++;

    if (maxLife != double.infinity) {
      opacity = 1.0 - (life / maxLife);
      if (life >= maxLife) reset();
    }

    if (x < 0 || x > 1 || y < 0 || y > 1) {
      if (maxLife == double.infinity) reset();
    }
  }

  void reset() {
    x = math.Random().nextDouble();
    y = math.Random().nextDouble();
    speedX = (math.Random().nextDouble() - 0.5) * 0.002;
    speedY = (math.Random().nextDouble() - 0.5) * 0.002;
    opacity = math.Random().nextDouble() * 0.5 + 0.2;
    life = 0;
    maxLife = double.infinity;
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;

  ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final paint = Paint()
        ..color = particle.color.withOpacity(particle.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
