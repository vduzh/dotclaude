---
name: antd-patterns
description: Ant Design patterns — Table with PagedResponse pagination, Form handling, message API for notifications, Modal confirmations for destructive actions
---

# Ant Design Patterns

Apply these patterns when building UI with Ant Design components.

## Table with PagedResponse Pagination

```typescript
const [page, setPage] = useState(1);
const [limit, setLimit] = useState(20);
const [sort, setSort] = useState('-createdAt');

const { data: response } = useQuery({
  queryKey: queryKeys.athletes.list({ page, limit, sort }),
  queryFn: () => athleteService.getList({ page, limit, sort }),
  placeholderData: keepPreviousData,
});

<Table
  dataSource={response?.data}
  rowKey="id"
  pagination={{
    current: response?.pagination.page,
    pageSize: response?.pagination.perPage,
    total: response?.pagination.total,
    showSizeChanger: true,
    showTotal: (total) => `Total ${total} items`,
    onChange: (p, size) => {
      setPage(p);
      setLimit(size);
    },
  }}
  onChange={(_, __, sorter) => {
    if (!Array.isArray(sorter) && sorter.field) {
      const dir = sorter.order === 'descend' ? '-' : '';
      setSort(`${dir}${sorter.field}`);
    }
  }}
/>
```

**Sorting:** Convert Ant Design's `{ field, order }` to JSON:API format (`name`, `-createdAt`).

## Form Handling

```typescript
const [form] = Form.useForm<AthleteCreate>();

const handleSubmit = async (values: AthleteCreate) => {
  await createAthlete.mutateAsync(values);
  form.resetFields();
  message.success('Athlete created');
};

<Form form={form} layout="vertical" onFinish={handleSubmit}>
  <Form.Item
    name="firstName"
    label="First Name"
    rules={[
      { required: true, message: 'First name is required' },
      { max: 50, message: 'Max 50 characters' },
    ]}
  >
    <Input />
  </Form.Item>

  <Form.Item
    name="email"
    label="Email"
    rules={[
      { required: true, message: 'Email is required' },
      { type: 'email', message: 'Invalid email' },
    ]}
  >
    <Input />
  </Form.Item>

  <Form.Item>
    <Button type="primary" htmlType="submit" loading={createAthlete.isPending}>
      Create
    </Button>
  </Form.Item>
</Form>
```

## Notifications via message API

```typescript
import { message } from 'antd';

// Success
message.success('Athlete created successfully');

// Error
message.error('Failed to create athlete');

// Loading (for async operations)
const hide = message.loading('Saving...', 0);
await saveData();
hide();
message.success('Saved');
```

## Modal Confirmations for Destructive Actions

```typescript
import { Modal } from 'antd';

const handleDelete = (id: string, name: string) => {
  Modal.confirm({
    title: 'Delete athlete?',
    content: `Are you sure you want to delete "${name}"? This action cannot be undone.`,
    okText: 'Delete',
    okType: 'danger',
    cancelText: 'Cancel',
    onOk: () => deleteAthlete.mutateAsync(id),
  });
};
```

## Entity Modal Pattern (Create/Edit)

```typescript
interface AthleteModalProps {
  open: boolean;
  athlete?: Athlete;        // undefined = create, defined = edit
  onClose: () => void;
  onSuccess: () => void;
}

const AthleteModal: React.FC<AthleteModalProps> = ({ open, athlete, onClose, onSuccess }) => {
  const [form] = Form.useForm<AthleteCreate>();
  const isEdit = !!athlete;

  useEffect(() => {
    if (open && athlete) {
      form.setFieldsValue(athlete);
    }
  }, [open, athlete, form]);

  const handleFinish = async (values: AthleteCreate) => {
    if (isEdit) {
      await updateAthlete.mutateAsync({ id: athlete.id, ...values });
    } else {
      await createAthlete.mutateAsync(values);
    }
    form.resetFields();
    onSuccess();
    onClose();
  };

  return (
    <Modal
      title={isEdit ? 'Edit Athlete' : 'New Athlete'}
      open={open}
      onCancel={onClose}
      onOk={() => form.submit()}
      confirmLoading={createAthlete.isPending || updateAthlete.isPending}
    >
      <Form form={form} layout="vertical" onFinish={handleFinish}>
        {/* fields */}
      </Form>
    </Modal>
  );
};
```
