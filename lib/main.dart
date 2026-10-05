DropdownButtonFormField<String>(
  initialValue: settings.provider,
  decoration:
      const InputDecoration(
    labelText: 'Provider',
  ),
  items: const [
    DropdownMenuItem(
      value: 'OpenRouter',
      child: Text('OpenRouter'),
    ),
    DropdownMenuItem(
      value: 'OpenAI',
      child: Text('OpenAI'),
    ),
    DropdownMenuItem(
      value: 'Gateway',
      child: Text('Gateway'),
    ),
    DropdownMenuItem(
      value: 'Custom',
      child: Text('Custom API'),
    ),
  ],
  onChanged: _providerChanged,
),
