export interface Widget {
  id: string;
  name: string;
}

export class WidgetClient {
  constructor(private readonly baseUrl: string) {}

  async getWidget(id: string): Promise<Widget> {
    const response = await fetch(`${this.baseUrl}/widgets/${id}`);

    if (!response.ok) {
      throw new Error(`GET /widgets/${id} failed with ${response.status}`);
    }

    return (await response.json()) as Widget;
  }
}
