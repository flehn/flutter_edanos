import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Education screen explaining sugar, fat, and fiber
class EducationInfoScreen extends StatelessWidget {
  const EducationInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Sugar & Fat'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('What is Sugar?'),
            const SizedBox(height: 8),
            _bodyText(
              'When we talk about table sugar (sucrose) or added sugar we are talking about a disaccharide (two sugars bonded together). It is roughly a 50/50 split of:',
            ),
            const SizedBox(height: 8),
            _bulletItem('Glucose', 'The energy of cells.'),
            _bulletItem('Fructose', 'The sweet molecule.'),
            const SizedBox(height: 8),
            _bodyText(
              'While they look similar chemically (both have the formula C\u2086H\u2081\u2082O\u2086), the body processes them in completely different ways. This difference is the key to understanding fat production.',
            ),
            const SizedBox(height: 24),
            _sectionTitle('2. The Tale of Two Sugars'),
            const SizedBox(height: 16),
            _subSectionTitle('Glucose: "The Fuel"'),
            const SizedBox(height: 8),
            _bulletPoint('Where it goes: Every cell in your body (brain, heart, muscles) uses glucose for energy.'),
            _bulletPoint('How it is processed: When you eat glucose, it enters your bloodstream. Your pancreas releases insulin to open the "doors" of your cells so the energy can get in.'),
            _bulletPoint('Storage: Most glucose is burned for energy immediately. The excess is stored in your muscles and liver as glycogen (a non-toxic storage form).'),
            _bulletPoint('Fat Risk: Only about 20% of glucose hits the liver. The liver only turns glucose into fat if your glycogen stores are completely full (which is rare unless you are vastly overeating).'),
            const SizedBox(height: 16),
            _subSectionTitle('Fructose: "The Burden"'),
            const SizedBox(height: 8),
            _bulletPoint('Where it goes: Virtually no cell in your body uses fructose for energy. It goes straight to the liver.'),
            _bulletPoint('How it is processed: The liver is the only organ that can metabolize fructose.'),
            _bulletPoint('Fat Risk: Since 100% of the fructose hits the liver at once, it overwhelms the liver\'s capacity to process it. It acts metabolically very similar to alcohol (ethanol), which is also processed exclusively by the liver.'),
            const SizedBox(height: 24),
            _sectionTitle('3. How They Work Together to Make Fat (De Novo Lipogenesis)'),
            const SizedBox(height: 8),
            _bodyText(
              'The reason sugar is so fattening is that glucose and fructose work as a "tag team" to drive fat production. This process is called De Novo Lipogenesis (making new fat).',
            ),
            const SizedBox(height: 12),
            _bodyText('Here is the step-by-step mechanism:'),
            const SizedBox(height: 8),
            _numberedItem('1', 'The Setup (Glucose spikes Insulin)',
              'You eat sugar. The glucose component spikes your blood sugar, causing your pancreas to pump out insulin. Insulin is the "fat storage hormone"\u2014it tells your body to stop burning fat and start storing energy.'),
            _numberedItem('2', 'The Overload (Fructose hits the Liver)',
              'Simultaneously, the fructose component rushes to your liver. Because the rest of the body can\'t use it, the liver\'s mitochondria (energy factories) get overwhelmed.'),
            _numberedItem('3', 'The Conversion',
              'The mitochondria cannot burn the fructose fast enough. To save itself from damage, the liver converts this excess citrate (a byproduct of fructose metabolism) into VLDL (Very Low-Density Lipoprotein).'),
            _numberedItem('4', 'The Result', ''),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText('VLDL is fat.'),
                  const SizedBox(height: 4),
                  _bulletPoint('Some of it lodges in the liver (causing Fatty Liver Disease).'),
                  _bulletPoint('Some of it is sent out into the bloodstream as triglycerides (causing heart disease risk).'),
                  _bulletPoint('Some of it is stored as visceral fat (the dangerous belly fat).'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _highlightBox(
              'In summary: The glucose raises the insulin (opening the door for fat storage), and the fructose provides the raw material that the liver turns directly into fat.',
            ),
            const SizedBox(height: 24),
            const Divider(color: AppTheme.textTertiary),
            const SizedBox(height: 24),
            _sectionTitle('How Fiber Stops Fat Creation'),
            const SizedBox(height: 8),
            _bodyText(
              'Fat creation (De Novo Lipogenesis) happens when the liver is overwhelmed by a tsunami of sugar (specifically fructose) and signaled to store it by insulin (triggered by glucose).',
            ),
            const SizedBox(height: 8),
            _bodyText(
              'Fiber stops this process by changing how fast that sugar hits your system. It essentially turns a "tsunami" into a manageable "stream."',
            ),
            const SizedBox(height: 20),
            _subSectionTitle('1. The "Gel" Barrier (Stopping the Tsunami)'),
            const SizedBox(height: 8),
            _bodyText(
              'Soluble and insoluble fiber work together to form a viscous gel that coats the inside of your small intestine (the duodenum). This gel acts like a physical barrier or a net.',
            ),
            const SizedBox(height: 8),
            _bulletPoint('Without Fiber: The sugar molecules (glucose and fructose) hit the intestinal wall immediately, rush into the bloodstream, and flood the liver all at once.'),
            _bulletPoint('With Fiber: The sugar is trapped inside this gel matrix. The digestive enzymes have to work much harder to find the sugar and break it down. This slows the entire process down significantly.'),
            const SizedBox(height: 20),
            _subSectionTitle('2. Protecting the Liver (The Fructose Intervention)'),
            const SizedBox(height: 8),
            _bodyText('Remember that the liver turns fructose into fat only when it is overloaded.'),
            const SizedBox(height: 8),
            _bulletPoint('The Mechanism: Because the fiber "gel" slows down absorption, the fructose hits the liver in a slow trickle rather than a massive wave.'),
            _bulletPoint('The Result: The liver\'s mitochondria have enough time to process this slow trickle of fructose into energy (ATP) or store it safely as glycogen.'),
            _bulletPoint('Fat Prevention: Because the liver isn\'t overwhelmed, it never needs to trigger De Novo Lipogenesis. The fructose is used, not turned into liver fat or VLDL (triglycerides).'),
            const SizedBox(height: 20),
            _subSectionTitle('3. Damping the Signal (The Glucose/Insulin Intervention)'),
            const SizedBox(height: 8),
            _bodyText('Fiber also interferes with the Insulin signal that tells your body to store fat.'),
            const SizedBox(height: 8),
            _bulletPoint('The Mechanism: Because glucose is also trapped in the fiber gel, it enters the bloodstream slowly.'),
            _bulletPoint('The Result: Instead of a sharp "spike" in blood sugar, you get a gentle "hill."'),
            _bulletPoint('Fat Prevention: Because blood sugar doesn\'t spike, the pancreas doesn\'t need to scream with a massive release of insulin.'),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bulletPoint('Low Insulin = The body stays in "fat burning" mode.'),
                  _bulletPoint('High Insulin = The body locks fat into cells and demands more storage.'),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey.withOpacity(0.2), width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: 0,
          onTap: (index) {
            Navigator.of(context).pop();
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.format_list_bulleted),
              activeIcon: Icon(Icons.format_list_bulleted),
              label: 'Food Log',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              activeIcon: Icon(Icons.camera_alt),
              label: 'Add Food',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.track_changes_outlined),
              activeIcon: Icon(Icons.track_changes),
              label: 'Goals',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        height: 1.4,
      ),
    );
  }

  static Widget _subSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.primaryBlue,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    );
  }

  static Widget _bodyText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 15,
        height: 1.6,
      ),
    );
  }

  static Widget _bulletItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('\u2022 ', style: TextStyle(color: AppTheme.primaryBlue, fontSize: 15)),
          Text(
            '$title: ',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('\u2022 ', style: TextStyle(color: AppTheme.textTertiary, fontSize: 15, height: 1.6)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _numberedItem(String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: AppTheme.primaryBlue,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _highlightBox(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 15,
          height: 1.6,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
