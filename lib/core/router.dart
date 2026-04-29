import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plexus/core/models/user_type.dart';
import 'package:plexus/core/providers/auth_provider.dart';
import 'package:plexus/core/providers/user_provider.dart';
import 'package:plexus/presentation/screens/splash_screen.dart';
import 'package:plexus/presentation/screens/auth/login_screen.dart';
import 'package:plexus/presentation/screens/auth/signup_screen.dart';
import 'package:plexus/presentation/screens/auth/verification_screen.dart';
import 'package:plexus/presentation/screens/auth/forgot_password_screen.dart';
import 'package:plexus/presentation/screens/auth/reset_password_screen.dart';
import 'package:plexus/presentation/screens/cart_screen.dart';
import 'package:plexus/presentation/screens/categories_screen.dart';
import 'package:plexus/presentation/screens/category_products_screen.dart';
import 'package:plexus/presentation/screens/chat_screen.dart';
import 'package:plexus/presentation/screens/confirmation_screen.dart';
import 'package:plexus/presentation/screens/home_screen.dart';
import 'package:plexus/presentation/screens/messages_screen.dart';
import 'package:plexus/presentation/screens/order_history_screen.dart';
import 'package:plexus/presentation/screens/order_detail_screen.dart';
import 'package:plexus/presentation/screens/payment_methods_screen.dart';
import 'package:plexus/presentation/screens/payment_screen.dart';
import 'package:plexus/presentation/screens/product_detail_screen.dart';
import 'package:plexus/presentation/screens/profile_screen.dart';
import 'package:plexus/presentation/screens/seller_hub_screen.dart';
import 'package:plexus/presentation/screens/notifications_screen.dart';
import 'package:plexus/presentation/screens/favorites_screen.dart';
import 'package:plexus/presentation/screens/referral_screen.dart';
import 'package:plexus/presentation/screens/dispute_screen.dart';
import 'package:plexus/presentation/screens/add_product_screen.dart';
import 'package:plexus/presentation/screens/edit_profile_screen.dart';
import 'package:plexus/presentation/screens/shipping_address_screen.dart'; // IMPORT AJOUTÉ
import 'package:plexus/presentation/scaffold_with_nav_bar.dart';
import 'package:provider/provider.dart';

GoRouter createRouter(BuildContext context) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authProvider,
    redirect: (BuildContext context, GoRouterState state) {
      final bool loggedIn = authProvider.isAuthenticated;
      final bool isAuthRoute = state.matchedLocation == '/login' || 
                               state.matchedLocation == '/signup' ||
                               state.matchedLocation == '/verify' ||
                               state.matchedLocation == '/forgot-password' ||
                               state.matchedLocation == '/reset-password' ||
                               state.matchedLocation == '/splash';

      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn && (state.matchedLocation == '/login' || state.matchedLocation == '/signup' || state.matchedLocation == '/splash')) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/verify', builder: (context, state) => const VerificationScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (context, state) => const ResetPasswordScreen()),
      
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home', 
              builder: (context, state) => const HomeScreen(), 
              routes: [
                GoRoute(path: 'product/:id', builder: (context, state) => ProductDetailScreen(productId: state.pathParameters['id']!)),
                GoRoute(path: 'notifications', builder: (context, state) => const NotificationsScreen()),
              ]
            )
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/categories', builder: (context, state) => const CategoriesScreen(), routes: [
              GoRoute(path: ':name', builder: (context, state) => CategoryProductsScreen(categoryName: state.pathParameters['name']!)),
            ])
          ]),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cart',
                builder: (context, state) => const CartScreen(),
                routes: [
                  GoRoute(path: 'payment', builder: (context, state) => PaymentScreen(productData: state.extra as Map<String, dynamic>?)),
                  GoRoute(path: 'confirmation', builder: (context, state) => ConfirmationScreen(order: state.extra as Map<String, dynamic>?)),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/messages', 
                builder: (context, state) => const ConversationsScreen(), 
                routes: [
                  GoRoute(
                    path: 'chat/:id', 
                    builder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      return ChatScreen(
                        conversationId: state.pathParameters['id']!, 
                        otherName: extra?['otherName'], 
                        productTitle: extra?['productTitle'],
                        orderId: extra?['orderId'],
                      );
                    }
                  )
                ]
              )
            ]
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) {
                  final userType = Provider.of<UserProvider>(context, listen: false).userType;
                  return userType == UserType.seller ? const SellerHubScreen() : const ProfileScreen();
                },
                routes: [
                  GoRoute(path: 'edit', builder: (context, state) => const EditProfileScreen()),
                  GoRoute(path: 'address', builder: (context, state) => const ShippingAddressScreen()), // ROUTE AJOUTÉE
                  GoRoute(path: 'add-product', builder: (context, state) => AddProductScreen(initialProduct: state.extra as Map<String, dynamic>?)),
                  GoRoute(path: 'referral', builder: (context, state) => const ReferralScreen()),
                  GoRoute(path: 'orders', builder: (context, state) => const OrderHistoryScreen(), routes: [
                    GoRoute(path: 'detail', builder: (context, state) => OrderDetailScreen(order: state.extra as Map<String, dynamic>)),
                  ]),
                  GoRoute(path: 'payment-methods', builder: (context, state) => const PaymentMethodsScreen()),
                  GoRoute(path: 'favorites', builder: (context, state) => const FavoritesScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/dispute', builder: (context, state) => DisputeScreen(order: state.extra as Map<String, dynamic>)),
    ],
  );
}
